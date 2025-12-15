// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "lib/v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {IncentivesHook} from "../src/IncentivesHook.sol";
import {HookMiner} from "../test/HookMiner.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {
    SwapParams,
    ModifyLiquidityParams
} from "v4-core/types/PoolOperation.sol";
import {MockBrevisProof} from "../src/brevis/MockBrevisProof.sol";
import {SwapFeeLibrary} from "../src/SwapFeeLibrary.sol";
import "forge-std/console2.sol";

contract IncentivesHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    MockBrevisProof private brevisProofMock;

    IncentivesHook hook;
    PoolId poolId;

    address lp1; // <-- thêm
    address lp2; // <-- thêm
    address user;
    MockERC20 token0;
    MockERC20 token1;
    bytes32 private constant VK_HASH =
        0x179a48b8a2a08b246cd51cb7b78143db774a83ff75fad0d39cf0445e16773426;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        lp1 = address(0x111);
        lp2 = address(0x222);
        user = address(0x333);

        token0 = MockERC20(Currency.unwrap(currency0));
        token1 = MockERC20(Currency.unwrap(currency1));

        token0.transfer(lp1, 10000 ether);
        token1.transfer(lp1, 10000 ether);
        token0.transfer(lp2, 10000 ether);
        token1.transfer(lp2, 10000 ether);
        token0.transfer(user, 10000 ether);
        token1.transfer(user, 10000 ether);

        brevisProofMock = new MockBrevisProof();

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(IncentivesHook).creationCode,
            abi.encode( IPoolManager(address(manager)), address(brevisProofMock)
            // , "SpongeCake", "SC"
            )
        );
        console.log("Hook we found:");
        console.logAddress(hookAddress);

        hook = new IncentivesHook{salt: salt}(
            IPoolManager(address(manager)),
            address(brevisProofMock)
        );
        
        console.log("Hook deployed :");
        console.logAddress(address(hook));

        hook.setVkHash(VK_HASH);
        require(address(hook) == hookAddress, "hook address mismatch");
        key = PoolKey(
            currency0,
            currency1,
            SwapFeeLibrary.DYNAMIC_FEE_FLAG,
            60,
            IHooks(address(hook))
        );

        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(-120, 120, 10000 ether, 0),
            ZERO_BYTES
        );
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(-240, 240, 10000 ether, 0),
            ZERO_BYTES
        );
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(-540, 540, 10000 ether, 0),
            ZERO_BYTES
        );
    }

    function test_RewardDistribution() public {
        int24 activeLower = -120;
        int24 activeUpper = 120;

        int24 unactiveLower = -540;
        int24 unactiveUpper = -480;
        address POOL_MODIFY_LIQUIDITY_ROUTER = address(modifyLiquidityRouter);
        bytes32 saltlp1 = bytes32(keccak256(abi.encode("lp1")));
        bytes32 saltlp2 = bytes32(keccak256(abi.encode("lp2")));

        vm.prank(lp1);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(lp1);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.prank(lp2);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(lp2);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(user);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(user);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.prank(lp1);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(
                activeLower,
                activeUpper,
                1000 ether,
                saltlp1
            ),
            ZERO_BYTES
        );

        vm.prank(lp2);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(
                unactiveLower,
                unactiveUpper,
                1000 ether,
                saltlp2
            ),
            ZERO_BYTES
        );

        vm.warp(block.timestamp + 1 days);

        (, int24 tickBefore, , ) = manager.getSlot0(key.toId());
        console.log("Tick before:");
        console.logInt(tickBefore);

        BalanceDelta swapDelta = Deployers.swap(key, true, 1 ether, ZERO_BYTES);

        (, int24 tickAfter, , ) = manager.getSlot0(key.toId());
        console.log("Tick after:");
        console.logInt(tickAfter);
        bytes32 salt = bytes32(0);
        uint256 rewardLP1 = hook.earned(
            key,
            activeLower,
            activeUpper,
            POOL_MODIFY_LIQUIDITY_ROUTER,
            saltlp1
        );
        uint256 rewardLP2 = hook.earned(
            key,
            unactiveLower,
            unactiveUpper,
            POOL_MODIFY_LIQUIDITY_ROUTER,
            saltlp2
        );

        console.log("Reward LP1:", rewardLP1);
        console.log("Reward LP2:", rewardLP2);

        //yêu cẩu rewardLP1 khác 0
        assert(rewardLP1 > 0);
        //yêu cầu rewardLP2 bằng 0
        assertEq(rewardLP2, 0);
    }

    //
    function test_low_vol_low_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        uint248 volatility = 20e18; // 20% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);
        console.log("Volatility set to:", hook.volatility());
        console.log("Volatility Expert", volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 400); // 4bps
        console.log("Swap fee charged (in hundredths of a bip):", fee);
    }

    function test_low_vol_mid_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        uint248 volatility = 20e18; // 20% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 832); // 8.3bps
    }

    function test_low_vol_high_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 100 ether;
        uint248 volatility = 20e18; // 20% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 2200); // 22bps
    }

    //
    // mid vol tests
    //
    function test_mid_vol_low_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        uint248 volatility = 60e18; // 60% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 800); // 8bps
    }

    function test_mid_vol_mid_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        uint248 volatility = 60e18; // 60% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 2097); // 20.9bps
    }

    function test_mid_vol_high_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 100 ether;
        uint248 volatility = 60e18; // 60% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 6200); // 62bps
    }

    //
    // mid vol tests
    //
    function test_high_vol_low_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 1 ether;
        uint248 volatility = 120e18; // 120% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 1400); // 14bps
    }

    function test_high_vol_mid_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 10 ether;
        uint248 volatility = 120e18; // 120% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 3994); // 39.9bps
    }

    function test_high_vol_high_amt() public {
        // Arrange
        uint256 balance1Before = currency1.balanceOfSelf();
        bool zeroForOne = true;
        int256 amountSpecified = 100 ether;
        uint248 volatility = 120e18; // 120% vol

        // simulate Brevis service callback update
        brevisProofMock.setMockOutput(
            bytes32(0),
            keccak256(abi.encodePacked(volatility)),
            VK_HASH
        );
        hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

        assertEq(hook.volatility(), volatility);

        // Act
        uint24 fee = hook.getFee(amountSpecified);
        BalanceDelta swapDelta = Deployers.swap(
            key,
            zeroForOne,
            amountSpecified,
            ZERO_BYTES
        );

        // Assert
        // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
        assertEq(fee, 12200); // 1.22%
    }
}
