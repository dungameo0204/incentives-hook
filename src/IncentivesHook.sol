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
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "v4-core/types/BeforeSwapDelta.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SwapFeeLibrary} from "./SwapFeeLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {
    SwapParams,
    ModifyLiquidityParams
} from "v4-core/types/PoolOperation.sol";
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

    uint256 public rewardRate = 5;
    uint256 public rewardReserve = 100e18;
    uint256 public periodFinish = block.timestamp + 7 days;

    /////////
    // ERRORs
    /////////

    error MustUseDynamicFee();

    /////////////////
    // State Variables
    ///////////////
    uint24 public constant BASE_FEE = 200; // 2bps

    /// the commission on basis points that is paid to the hook to cover Brevis service costs
    uint24 public constant HOOK_COMMISSION = 100; // 0.01%

    struct RewardInfo {
        uint256 rewardGrowthOutsideX128;
    }

    mapping(PoolId=> uint256) public rewardGrowthGlobalX128;
    mapping(PoolId=> uint256) public stakedLiquidity;
    mapping (PoolId => mapping(int24 => RewardInfo)) public ticks;
    mapping(PoolId => int24) private tickBeforeSwap;
    mapping(PoolId => mapping(bytes32 => uint256)) public rewardPerTokenInsideInitialX128;
    mapping(PoolId => mapping(bytes32 => uint256)) public amoutUnclaimed;

    mapping(PoolId => int24) private activeTick;

    mapping(PoolId => uint256) private _lastUpdated;

    constructor(
        IPoolManager _poolManager,
        address brevisProof
    )
        BaseHook(_poolManager)
        ERC20("SpongeCake", "SC")
        BrevisApp(IBrevisProof(brevisProof))
    {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
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

    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) internal override returns (bytes4) {
        //if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        PoolId id = key.toId();
        poolKey = key;
        activeTick[id] = tick; // We need to know where to begin
        _lastUpdated[id] = block.timestamp;

        return BaseHook.afterInitialize.selector;
    }

    // - DYNAMIC_FEE_FLAG = 0x800000
    // Check if the pool is enabled for dynamic fee
    function _beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) internal pure override returns (bytes4) {
        //isDynamicFee: in Hooks  >> from SwapFeeLibrary>> need to set to value 0x800000

        //

        return BaseHook.beforeInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        //takeCommission(key, swapParams);

        // Calculate how much fee shold be charged:
        uint24 fee = calculateFee(abs(swapParams.amountSpecified));

        fee = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG; // we need to apply override flag
        // We track all rewards for the previous active tick.
        _updateRewardsGrowthGlobal(key);
        (, int24 tick, , ) = poolManager.getSlot0(key.toId());
        tickBeforeSwap[key.toId()] = tick;
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            fee
        );
    }
    //  function takeCommission(PoolKey calldata key, IPoolManager.SwapParams calldata swapParams) internal {
    //         uint256 tokenAmount =
    //             swapParams.amountSpecified < 0 ? uint256(-swapParams.amountSpecified) : uint256(swapParams.amountSpecified);

    //         uint256 commissionAmt = Math.mulDiv(tokenAmount, HOOK_COMMISSION, 10000);

    //         // determine inbound token based on 0->1 or 1->0 swap
    //         Currency inbound = swapParams.zeroForOne ? key.currency0 : key.currency1;

    //         // take the inbound token from the PoolManager, debt is paid by the swapper via the swap router
    //         // (inbound token is added to hook's reserves)
    //         poolManager.take(inbound, address(this), commissionAmt);
    //     }
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId id = key.toId();
        (, int24 tick, , ) = poolManager.getSlot0(id);

        // console.log("Tick after:");
        // console.logInt(tick);

        // Update the tick after the swap so future rewards go to active tick
        activeTick[id] = tick;

        int24 zTick = tickBeforeSwap[id];
        // console.log("Tick before:");
        // console.logInt(zTick);

        if (zTick < tick) {
            for (int24 t = zTick; t < tick; t += key.tickSpacing) {
            ticks[id][t].rewardGrowthOutsideX128 =
                rewardGrowthGlobalX128[id] -
                ticks[id][t].rewardGrowthOutsideX128;
            }
        } else {
            for (int24 t = tick; t < zTick; t += key.tickSpacing) {
            ticks[id][t].rewardGrowthOutsideX128 =
                rewardGrowthGlobalX128[id] -
                ticks[id][t].rewardGrowthOutsideX128;
            }
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        // Let's update rewards so users don't lose them on removal
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
        bytes32 positionId = Position.calculatePositionKey(
            sender,
            params.tickLower,
            params.tickUpper,
            params.salt
        );
        uint128 liquidity = StateLibrary.getPositionLiquidity(
            poolManager,
            id,
            positionId
        );

        stakedLiquidity[id] -= liquidity;
        _updateReward(
            key,
            params.tickLower,
            params.tickUpper,
            sender,
            params.salt
        );
        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        // We use this hook to update state before a liquidity change has happened.
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
        bytes32 positionId = Position.calculatePositionKey(
            sender,
            params.tickLower,
            params.tickUpper,
            params.salt
        );
        uint128 liquidity = StateLibrary.getPositionLiquidity(
            poolManager,
            id,
            positionId
        );
        stakedLiquidity[id] += liquidity;
        _updateReward(
            key,
            params.tickLower,
            params.tickUpper,
            sender,
            params.salt
        );

        // console.log("salt when add liquidity:");
        // console.logBytes32(params.salt);
        // console.log("Address owner call add liquidity:");
        // console.logAddress(sender);
        // console.log("who add liquidity:");
        // console.logAddress(tx.origin);
        // console.log("Liquidity after add:", liquidity);
        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    // Internal Functions
    function _updateRewardsGrowthGlobal(PoolKey calldata key) internal {
        PoolId id = key.toId();
        uint256 timestamp = block.timestamp;
        uint256 timeDelta = timestamp - _lastUpdated[id]; // skip if second call in same block

        if (timeDelta != 0) {
            if (rewardReserve > 0) {
            uint256 reward = rewardRate * timeDelta;
            if (reward > rewardReserve) reward = rewardReserve; // give everything if expected is more than allocated
            if (stakedLiquidity[id] > 0) {
                // ^ This only exists to not burn all rewards if no staked liquidity
                rewardGrowthGlobalX128[id] +=
                (reward * FixedPoint128.Q128) /
                stakedLiquidity[id];
                rewardReserve -= reward;
            }
            }

            _lastUpdated[id] = timestamp;
        }
    }

    function getRewardGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        PoolKey calldata key
    ) public view returns (uint256 rewardGrowthInsideX128) {
        PoolId id = key.toId();
        RewardInfo storage lower = ticks[id][tickLower];
        RewardInfo storage upper = ticks[id][tickUpper];

        // calculate reward growth below
        uint256 rewardGrowthBelowX128;
        if (tickCurrent >= tickLower) {
            rewardGrowthBelowX128 = lower.rewardGrowthOutsideX128;
        } else {
            rewardGrowthBelowX128 =
            rewardGrowthGlobalX128[id] -
            lower.rewardGrowthOutsideX128;
        }

        // calculate reward growth above
        uint256 rewardGrowthAboveX128;
        if (tickCurrent < tickUpper) {
            rewardGrowthAboveX128 = upper.rewardGrowthOutsideX128;
        } else {
            rewardGrowthAboveX128 =
            rewardGrowthGlobalX128[id] -
            upper.rewardGrowthOutsideX128;
        }

        rewardGrowthInsideX128 =
            rewardGrowthGlobalX128[id] -
            rewardGrowthBelowX128 -
            rewardGrowthAboveX128;
    }
    function _updateReward(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        address owner,
        bytes32 salt
    ) internal {
        PoolId id = key.toId();
        _updateRewardsGrowthGlobal(key);

        // calculate new rewards
        uint256 rewardPerTokenInsideX128 = getRewardGrowthInside(
            tickLower,
            tickUpper,
            activeTick[id],
            key
        );

        bytes32 positionId = Position.calculatePositionKey(
            owner,
            tickLower,
            tickUpper,
            salt
        );
        uint128 liquidity = StateLibrary.getPositionLiquidity(
            poolManager,
            id,
            positionId
        );
        uint256 avaiable = ((rewardPerTokenInsideX128 -
            rewardPerTokenInsideInitialX128[id][positionId]) * uint256(liquidity)) /
            FixedPoint128.Q128;
        amoutUnclaimed[id][positionId] += avaiable;
        rewardPerTokenInsideInitialX128[id][positionId] = rewardPerTokenInsideX128;
    }

    // Interactions

    function _claimReward(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        address owner,
        bytes32 salt,
        uint256 amount
    ) external {
        PoolId id = key.toId();
        require(msg.sender == owner, "Not position owner");
        //update reward
        _updateReward(key, tickLower, tickUpper, owner, salt);
        bytes32 positionId = Position.calculatePositionKey(
            owner,
            tickLower,
            tickUpper,
            salt
        );
        require(amoutUnclaimed[id][positionId] >= amount, "Not enough reward");
        amoutUnclaimed[id][positionId] -= amount;
        // mint token to user
        _mint(msg.sender, amount);
    }

    function earned(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        address owner,
        bytes32 salt
    ) external view returns (uint256 claimable) {
        // current liquidity của position

        PoolId id = key.toId();
        bytes32 positionId = Position.calculatePositionKey(
            owner,
            tickLower,
            tickUpper,
            salt
        );
        uint128 liquidity = StateLibrary.getPositionLiquidity(
            poolManager,
            id,
            positionId
        );
        // console.log("Address owner when earned:");
        // console.logAddress(owner);
        // console.log("salt:");
        // console.logBytes32(salt);
        // console.log("rewardPerTokenInsideInitialX128[positionId]:", rewardPerTokenInsideInitialX128[positionId]);
        // console.log("liquidity when earned:", liquidity);

        // tính reward mới mà chưa update
        uint256 rewardPerTokenInsideX128 = getRewardGrowthInside(
            tickLower,
            tickUpper,
            activeTick[key.toId()],
            key
        );

        console.log("rewardPerTokenInsideX128:", rewardPerTokenInsideX128);

        uint256 pending = ((rewardPerTokenInsideX128 -
            rewardPerTokenInsideInitialX128[id][positionId]) * liquidity) /
            FixedPoint128.Q128;

        // cộng với reward đã lưu
        claimable = amoutUnclaimed[id][positionId] + pending;
    }

    ///////////////////
    // Brevis Functions
    ///////////////////

    // BrevisQuery contract will call our callback once Brevis backend submits the proof.
    function handleProofResult(
        bytes32,
        /*_requestId*/ bytes32 _vkHash,
        bytes calldata _circuitOutput
    ) internal override {
        // We need to check if the verifying key that Brevis used to verify the proof generated by our circuit is indeed
        // our designated verifying key. This proves that the _circuitOutput is authentic
        require(vkHash == _vkHash, "invalid vk");

        volatility = decodeOutput(_circuitOutput);

        emit VolatilityUpdated(volatility);
    }

    // In app circuit we have:
    // api.OutputUint(248, vol)
    function decodeOutput(bytes calldata o) internal pure returns (uint256) {
        uint248 vol = uint248(bytes31(o[0:31])); // vol is output as a uint248 (31 bytes)
        return uint256(vol);
    }

    function setVkHash(bytes32 _vkHash) external {
        vkHash = _vkHash;
    }

    ///////////////////
    // Helper Functions
    ///////////////////

    // Calculate Fee we will charge

    function calculateFee(uint256 volume) internal view returns (uint24) {
        uint256 constant_factor = 1e26;
        uint256 variable_fee = (sqrt(volume) * volatility) / constant_factor;
        return uint24(BASE_FEE + variable_fee);
    }

    function abs(int256 x) private pure returns (uint256) {
        if (x >= 0) {
            return uint256(x);
        }

        return uint256(-x);
    }

    // Get Fee
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
