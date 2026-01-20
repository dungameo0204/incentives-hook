// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Pool} from "v4-core/libraries/Pool.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {FixedPoint128} from "v4-core/libraries/FixedPoint128.sol";
import {Position} from "v4-core/libraries/Position.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {console} from "forge-std/console.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SwapFeeLibrary} from "./SwapFeeLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./brevis/BrevisApp.sol";
import "./brevis/IBrevisProof.sol";

contract IncentivesHook is BaseHook, ERC20, BrevisApp {
    using SwapFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using Pool for Pool.State;
    using StateLibrary for IPoolManager;

    event VolatilityUpdated(uint256 volatility);

    bytes32 public vkHash;
    uint256 public volatility;
    PoolKey public poolKey;

    // Reward Config: 1 Token/s, Reserve lớn để demo thoải mái
    uint256 public rewardRate = 1000000000000000000; 
    uint256 public rewardReserve = 1000000000000e18; 
    uint256 public periodFinish = block.timestamp + 7 days;

    error MustUseDynamicFee();

    uint24 public constant BASE_FEE = 200; // 2bps
    uint24 public constant HOOK_COMMISSION = 100; // 0.01%

    struct RewardInfo {
        uint256 rewardGrowthOutsideX128;
    }

    mapping(PoolId => uint256) public rewardGrowthGlobalX128;
    mapping(PoolId => uint256) public stakedLiquidity;
    mapping(PoolId => mapping(int24 => RewardInfo)) public ticks;
    mapping(PoolId => int24) private tickBeforeSwap;
    mapping(PoolId => mapping(bytes32 => uint256)) public rewardPerTokenInsideInitialX128;
    mapping(PoolId => mapping(bytes32 => uint256)) public amoutUnclaimed;
    mapping(PoolId => int24) private activeTick;
    mapping(PoolId => uint256) private _lastUpdated;

    constructor(IPoolManager _poolManager, address brevisProof)
        BaseHook(_poolManager)
        ERC20("SpongeCake", "SC")
        BrevisApp(IBrevisProof(brevisProof))
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // --- Initialization ---
    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        return BaseHook.beforeInitialize.selector;
    }

    function _afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        internal override returns (bytes4)
    {
        PoolId id = key.toId();
        poolKey = key;
        activeTick[id] = tick;
        _lastUpdated[id] = block.timestamp;
        return BaseHook.afterInitialize.selector;
    }

    // --- Swap Logic ---
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata swapParams, bytes calldata)
        internal override returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = calculateFee(abs(swapParams.amountSpecified));
        fee = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        
        // Update reward global trước khi swap làm thay đổi tick
        _updateRewardsGrowthGlobal(key);
        
        (, int24 tick,,) = poolManager.getSlot0(key.toId());
        tickBeforeSwap[key.toId()] = tick;
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal override returns (bytes4, int128)
    {
        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);
        activeTick[id] = tick;

        int24 zTick = tickBeforeSwap[id];
        // Tick crossing logic: Update rewardGrowthOutside
        if (zTick < tick) {
            for (int24 t = zTick; t < tick; t += key.tickSpacing) {
                ticks[id][t].rewardGrowthOutsideX128 = rewardGrowthGlobalX128[id] - ticks[id][t].rewardGrowthOutsideX128;
            }
        } else {
            for (int24 t = tick; t < zTick; t += key.tickSpacing) {
                ticks[id][t].rewardGrowthOutsideX128 = rewardGrowthGlobalX128[id] - ticks[id][t].rewardGrowthOutsideX128;
            }
        }
        return (BaseHook.afterSwap.selector, 0);
    }

    // --- Liquidity Logic ---
    function _beforeAddLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        internal override returns (bytes4)
    {
        _updateRewardsGrowthGlobal(key);
        return BaseHook.beforeAddLiquidity.selector;
    }

function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData 
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId id = key.toId();
        
        // 1. Nếu có thay đổi thanh khoản (delta != 0), cập nhật như bình thường
        if (params.liquidityDelta != 0) {
            uint128 liquidityAdded = uint128(uint256(params.liquidityDelta));
            stakedLiquidity[id] += liquidityAdded;
            _updateReward(key, params.tickLower, params.tickUpper, sender, params.salt, params.liquidityDelta);
        }

        // 2. LOGIC RÚT THƯỞNG QUA HOOK DATA
        // Nếu hookData không rỗng, ta decode xem user có muốn claim không
        if (hookData.length > 0) {
            bool shouldClaim = abi.decode(hookData, (bool));
            if (shouldClaim) {
                // Nếu delta == 0, ta cần update reward thủ công trước khi claim để đảm bảo số liệu mới nhất
                if (params.liquidityDelta == 0) {
                     _updateReward(key, params.tickLower, params.tickUpper, sender, params.salt, 0);
                }
                _claimReward(key, params.tickLower, params.tickUpper, sender, params.salt);
            }
        }

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _beforeRemoveLiquidity(address, PoolKey calldata key, ModifyLiquidityParams calldata, bytes calldata)
        internal override returns (bytes4)
    {
        _updateRewardsGrowthGlobal(key);
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId id = key.toId();
        
        // 1. Trừ Staked Liquidity
        uint128 liquidityRemoved = uint128(uint256(-params.liquidityDelta));
        stakedLiquidity[id] -= liquidityRemoved;

        // 2. Cập nhật Reward
        _updateReward(key, params.tickLower, params.tickUpper, sender, params.salt, params.liquidityDelta);
        _claimReward(key, params.tickLower, params.tickUpper, sender, params.salt);
        // 3. Auto Claim khi remove liquidity

        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // --- Core Reward Logic ---
    
    function _updateRewardsGrowthGlobal(PoolKey calldata key) internal {
        PoolId id = key.toId();
        uint256 timestamp = block.timestamp;
        uint256 timeDelta = timestamp - _lastUpdated[id];

        if (timeDelta != 0) {
            if (rewardReserve > 0) {
                uint256 reward = rewardRate * timeDelta;
                if (reward > rewardReserve) reward = rewardReserve;
                if (stakedLiquidity[id] > 0) {
                    rewardGrowthGlobalX128[id] += (reward * FixedPoint128.Q128) / stakedLiquidity[id];
                    rewardReserve -= reward;
                }
            }
            _lastUpdated[id] = timestamp;
        }
    }

    function getRewardGrowthInside(int24 tickLower, int24 tickUpper, int24 tickCurrent, PoolKey calldata key)
        public view returns (uint256 rewardGrowthInsideX128)
    {
        PoolId id = key.toId();
        RewardInfo storage lower = ticks[id][tickLower];
        RewardInfo storage upper = ticks[id][tickUpper];

        uint256 rewardGrowthBelowX128;
        if (tickCurrent >= tickLower) {
            rewardGrowthBelowX128 = lower.rewardGrowthOutsideX128;
        } else {
            rewardGrowthBelowX128 = rewardGrowthGlobalX128[id] - lower.rewardGrowthOutsideX128;
        }

        uint256 rewardGrowthAboveX128;
        if (tickCurrent < tickUpper) {
            rewardGrowthAboveX128 = upper.rewardGrowthOutsideX128;
        } else {
            rewardGrowthAboveX128 = rewardGrowthGlobalX128[id] - upper.rewardGrowthOutsideX128;
        }

        rewardGrowthInsideX128 = rewardGrowthGlobalX128[id] - rewardGrowthBelowX128 - rewardGrowthAboveX128;
    }

    function _updateReward(
        PoolKey calldata key, 
        int24 tickLower, 
        int24 tickUpper, 
        address owner, 
        bytes32 salt,
        int256 liquidityDelta
    ) internal {
        PoolId id = key.toId();
        _updateRewardsGrowthGlobal(key); // Ensure global is up to date

        uint256 rewardPerTokenInsideX128 = getRewardGrowthInside(tickLower, tickUpper, activeTick[id], key);

        // Lấy Liquidity HIỆN TẠI 
        bytes32 positionId = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
        uint128 currentLiquidity = StateLibrary.getPositionLiquidity(poolManager, id, positionId);

        // Tính Liquidity CŨ 
        uint128 prevLiquidity;
        if (liquidityDelta > 0) {
            prevLiquidity = currentLiquidity - uint128(uint256(liquidityDelta));
        } else {
            prevLiquidity = currentLiquidity + uint128(uint256(-liquidityDelta));
        }

        // CHỈ TÍNH THƯỞNG TRÊN LIQUIDITY CŨ
        if (prevLiquidity > 0) {
            uint256 available = (
                (rewardPerTokenInsideX128 - rewardPerTokenInsideInitialX128[id][positionId]) * uint256(prevLiquidity)
            ) / FixedPoint128.Q128;
            amoutUnclaimed[id][positionId] += available;
        }

        // CẬP NHẬT SNAPSHOT MỚI 
        rewardPerTokenInsideInitialX128[id][positionId] = rewardPerTokenInsideX128;
    }

    // --- User Interactions ---

    function _claimReward(PoolKey calldata key, int24 tickLower, int24 tickUpper, address owner, bytes32 salt) internal {
        PoolId id = key.toId();
        _updateReward(key, tickLower, tickUpper, owner, salt, 0); 

        bytes32 positionId = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
        uint256 rewardToSend = amoutUnclaimed[id][positionId];

        if (rewardToSend > 0) {
            amoutUnclaimed[id][positionId] = 0;
            _mint(tx.origin, rewardToSend);
        }
    }

    // --- View / Helper Functions ---

    function _getExtrapolatedGlobalGrowth(PoolKey calldata key) internal view returns (uint256) {
        PoolId id = key.toId();
        uint256 currentGrowth = rewardGrowthGlobalX128[id];
        uint256 last = _lastUpdated[id];
        
        if (block.timestamp > last && stakedLiquidity[id] > 0 && rewardReserve > 0) {
            uint256 timeDelta = block.timestamp - last;
            uint256 reward = rewardRate * timeDelta;
            if (reward > rewardReserve) reward = rewardReserve;
            currentGrowth += (reward * FixedPoint128.Q128) / stakedLiquidity[id];
        }
        return currentGrowth;
    }

    function _getRewardGrowthInsideVirtual(
        PoolKey calldata key, 
        int24 tickLower, 
        int24 tickUpper, 
        uint256 currentGlobalGrowth
    ) internal view returns (uint256) {
        PoolId id = key.toId();
        int24 _activeTick = activeTick[id];
        
        uint256 growthBelow;
        if (_activeTick >= tickLower) {
            growthBelow = ticks[id][tickLower].rewardGrowthOutsideX128;
        } else {
            growthBelow = currentGlobalGrowth - ticks[id][tickLower].rewardGrowthOutsideX128;
        }

        uint256 growthAbove;
        if (_activeTick < tickUpper) {
            growthAbove = ticks[id][tickUpper].rewardGrowthOutsideX128;
        } else {
            growthAbove = currentGlobalGrowth - ticks[id][tickUpper].rewardGrowthOutsideX128;
        }

        return currentGlobalGrowth - growthBelow - growthAbove;
    }

    function earned(PoolKey calldata key, int24 tickLower, int24 tickUpper, address owner, bytes32 salt)
        external view returns (uint256 claimable)
    {
        PoolId id = key.toId();
        uint256 growthGlobal = _getExtrapolatedGlobalGrowth(key);
        uint256 rewardGrowthInsideX128 = _getRewardGrowthInsideVirtual(key, tickLower, tickUpper, growthGlobal);

        bytes32 positionId = Position.calculatePositionKey(owner, tickLower, tickUpper, salt);
        uint128 liquidity = StateLibrary.getPositionLiquidity(poolManager, id, positionId);

        uint256 pending = ((rewardGrowthInsideX128 - rewardPerTokenInsideInitialX128[id][positionId]) * uint256(liquidity))
            / FixedPoint128.Q128;

        claimable = amoutUnclaimed[id][positionId] + pending;
    }

    // --- Brevis & Helpers ---
    function handleProofResult(bytes32, bytes32 _vkHash, bytes calldata _circuitOutput) internal override {
        require(vkHash == _vkHash, "invalid vk");
        volatility = decodeOutput(_circuitOutput);
        emit VolatilityUpdated(volatility);
    }

    function decodeOutput(bytes calldata o) internal pure returns (uint256) {
        uint248 vol = uint248(bytes31(o[0:31])); 
        return uint256(vol);
    }

    function setVkHash(bytes32 _vkHash) external {
        vkHash = _vkHash;
    }

    function calculateFee(uint256 volume) internal view returns (uint24) {
        uint256 constant_factor = 1e26;
        uint256 variable_fee = (sqrt(volume) * volatility) / constant_factor;
        return uint24(BASE_FEE + variable_fee);
    }

    function abs(int256 x) private pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    function getFee(int256 amnt) external view returns (uint24) {
        return calculateFee(abs(amnt));
    }

    function sqrt(uint256 x) public pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}