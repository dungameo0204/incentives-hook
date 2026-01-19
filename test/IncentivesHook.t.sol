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
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
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
    bytes32 private constant VK_HASH = 0x179a48b8a2a08b246cd51cb7b78143db774a83ff75fad0d39cf0445e16773426;

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
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(IncentivesHook).creationCode,
            abi.encode(IPoolManager(address(manager)), address(brevisProofMock))
        );
        // , "SpongeCake", "SC"

        console.log("Hook we found:");
        console.logAddress(hookAddress);

        hook = new IncentivesHook{salt: salt}(IPoolManager(address(manager)), address(brevisProofMock));

        console.log("Hook deployed :");
        console.logAddress(address(hook));

        hook.setVkHash(VK_HASH);
        require(address(hook) == hookAddress, "hook address mismatch");
        key = PoolKey(currency0, currency1, SwapFeeLibrary.DYNAMIC_FEE_FLAG, 60, IHooks(address(hook)));

        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-120, 120, 10000 ether, 0), ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-240, 240, 10000 ether, 0), ZERO_BYTES);
        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-540, 540, 10000 ether, 0), ZERO_BYTES);
    }

   function test_RemoveLiquidity_And_Claim() public {
        // --- SETUP ---
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint256 liquidityAmount = 1000 ether;
        bytes32 salt = keccak256(abi.encode("lp1"));
        
        // SỬA LỖI SHADOWING: Đổi tên biến user -> claimUser
        address claimUser = address(0x123ACB); 

        // Mint token cho claimUser
        token0.mint(claimUser, 10000 ether);
        token1.mint(claimUser, 10000 ether);

        // Approve Router
        vm.startPrank(claimUser);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        // 1. ADD LIQUIDITY
        console.log("--- 1. User Adding Liquidity ---");
        vm.prank(claimUser); 
        
        // SỬA LỖI STRUCT: Dùng trực tiếp ModifyLiquidityParams (bỏ IPoolManager.)
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({ 
                tickLower: tickLower, 
                tickUpper: tickUpper, 
                liquidityDelta: int256(liquidityAmount), 
                salt: salt
            }),
            ZERO_BYTES
        );

        // 2. WAIT & SWAP
        vm.warp(block.timestamp + 100);
        Deployers.swap(key, true, 0.0001 ether, ZERO_BYTES);

        uint256 pendingReward = hook.earned(key, tickLower, tickUpper, address(modifyLiquidityRouter), salt);
        console.log("Pending Reward before remove:", pendingReward);
        assertGt(pendingReward, 0, "Phai co reward tich luy");

        // 3. REMOVE LIQUIDITY
        console.log("--- 3. User Removing Liquidity ---");
        uint256 userRewardBalanceBefore = hook.balanceOf(claimUser);
        
        vm.prank(claimUser,claimUser); 
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({ 
                tickLower: tickLower, 
                tickUpper: tickUpper, 
                liquidityDelta: -int256(liquidityAmount), // Rút số âm
                salt: salt
            }),
            ZERO_BYTES
        );

        // 4. CHECK RESULT
        uint256 userRewardBalanceAfter = hook.balanceOf(claimUser);
        console.log("User Reward Balance After:", userRewardBalanceAfter);

        // Kiểm tra tiền về ví User (claimUser) chứ không phải Router
        assertGt(userRewardBalanceAfter, userRewardBalanceBefore, "User phai nhan duoc token thuong");
    }

    function test_RewardDebt_Fix() public {
        // --- CẤU HÌNH ---
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint256 liquidityAmount = 1000 ether;
        bytes32 salt1 = keccak256(abi.encode("lp1"));
        bytes32 salt2 = keccak256(abi.encode("lp2"));

        // Approve token cho router
        vm.startPrank(lp1);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lp2);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        vm.stopPrank();

        // 1. LP1 ADD LIQUIDITY (Người đến sớm)
        vm.prank(lp1);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(tickLower, tickUpper, int256(liquidityAmount), salt1),
            ZERO_BYTES
        );

        // 2. THỜI GIAN TRÔI QUA (Tích lũy thưởng)
        vm.warp(block.timestamp + 100); // Trôi qua 100 giây
        
        // Swap một chút để trigger update reward global
        // (Swap cực nhỏ để không làm lệch tick ra ngoài range)
        Deployers.swap(key, true, 0.0001 ether, ZERO_BYTES);

        // 3. LP2 ADD LIQUIDITY (Người đến muộn)
        // LP2 nhảy vào pool SAU KHI reward đã được tích lũy 100 giây
        vm.prank(lp2);
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(tickLower, tickUpper, int256(liquidityAmount), salt2),
            ZERO_BYTES
        );

        // 4. KIỂM TRA KẾT QUẢ (Moment of Truth)
        
        // Check thưởng của LP1 (Phải > 0)
        uint256 rewardLP1 = hook.earned(key, tickLower, tickUpper, address(modifyLiquidityRouter), salt1); // Lưu ý owner là Router nếu dùng script deployer cũ, hoặc là lp1 tùy setup
        // Ở đây mình giả định owner là lp1 nếu bạn dùng router mới, hoặc router address nếu router giữ NFT. 
        // Để chắc ăn nhất trong môi trường test Foundry chuẩn: owner thường là msg.sender (lp1/lp2) nếu router transfer NFT về.
        // Nhưng với ModifyLiquidityRouter cơ bản, owner là LP1/LP2.
        
        // Sửa lại owner thành lp1 và lp2 cho chắc chắn (nếu Router transfer NFT về user)
        // Nếu dùng Router cơ bản của V4 test, nó không mint NFT, nó giữ position.
        // Cứ thử check với owner = lp1 trước.
        
        // **LƯU Ý:** Để test hook.earned chạy đúng, hãy dùng đúng address owner mà Hook ghi nhận.
        // Trong test script thường là address(modifyLiquidityRouter) hoặc msg.sender.
        // Mình sẽ dùng biến lp1 và lp2 đại diện.

        // Vì trong hàm modifyLiquidity của TestRouter, msg.sender là người gọi.
        uint256 rewardLP1_Check = hook.earned(key, tickLower, tickUpper, lp1, salt1);
        // Nếu rewardLP1_Check == 0 thì thử đổi owner thành address(modifyLiquidityRouter)
        if (rewardLP1_Check == 0) {
             rewardLP1_Check = hook.earned(key, tickLower, tickUpper, address(modifyLiquidityRouter), salt1);
        }

        uint256 rewardLP2_Check = hook.earned(key, tickLower, tickUpper, lp2, salt2);
        if (rewardLP2_Check == 0 && rewardLP1_Check > 0) {
             // Thử check lại với router address cho lp2 để chắc chắn không phải do sai address
             uint256 temp = hook.earned(key, tickLower, tickUpper, address(modifyLiquidityRouter), salt2);
             // Nếu temp > 0 thì tức là LP2 bị tính sai address, gán lại
             if (temp > 0) rewardLP2_Check = temp;
        }

        console.log("-------------------------------------------");
        console.log("Reward LP1 (Da o trong pool 100s): ", rewardLP1_Check);
        console.log("Reward LP2 (Vua moi vao pool):     ", rewardLP2_Check);
        console.log("-------------------------------------------");

        // 5. ASSERTIONS (Điều kiện Pass)
        
        // LP1 phải có thưởng
        assertGt(rewardLP1_Check, 0, "LP1 phai co thuong");

        // LP2 vừa vào phải KHÔNG CÓ thưởng (hoặc rất nhỏ do chênh lệch 1 block/giây lúc swap)
        // Nếu code cũ (lỗi): rewardLP2 sẽ xấp xỉ rewardLP1
        // Nếu code mới (đúng): rewardLP2 sẽ bằng 0
        assertEq(rewardLP2_Check, 0, "LP2 vua vao thi reward phai bang 0");
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
            key, ModifyLiquidityParams(activeLower, activeUpper, 1000 ether, saltlp1), ZERO_BYTES
        );

        vm.prank(lp2);
        modifyLiquidityRouter.modifyLiquidity(
            key, ModifyLiquidityParams(unactiveLower, unactiveUpper, 1000 ether, saltlp2), ZERO_BYTES
        );

        vm.warp(block.timestamp + 1 days);

        (, int24 tickBefore,,) = manager.getSlot0(key.toId());
        console.log("Tick before:");
        console.logInt(tickBefore);

        BalanceDelta swapDelta = Deployers.swap(key, true, 0.001 ether, ZERO_BYTES);

        (, int24 tickAfter,,) = manager.getSlot0(key.toId());
        console.log("Tick after:");
        console.logInt(tickAfter);
        bytes32 salt = bytes32(0);
        uint256 rewardLP1 = hook.earned(key, activeLower, activeUpper, POOL_MODIFY_LIQUIDITY_ROUTER, saltlp1);
        uint256 rewardLP2 = hook.earned(key, unactiveLower, unactiveUpper, POOL_MODIFY_LIQUIDITY_ROUTER, saltlp2);

        console.log("Reward LP1:", rewardLP1);
        console.log("Reward LP2:", rewardLP2);

        //yêu cẩu rewardLP1 khác 0
        assert(rewardLP1 > 0);
        //yêu cầu rewardLP2 bằng 0
        assertEq(rewardLP2, 0);
        vm.warp(block.timestamp + 1 days);
        swapDelta = Deployers.swap(key, true, 0.001 ether, ZERO_BYTES);
        uint256 rewardLP11day = hook.earned(key, -120, 120, POOL_MODIFY_LIQUIDITY_ROUTER, saltlp1);
        console.log("Reward LP11day:", rewardLP11day);
         assert(rewardLP11day > rewardLP1);

        
    }

    //
//     function test_low_vol_low_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 1 ether;
//         uint248 volatility = 20e18; // 20% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);
//         console.log("Volatility set to:", hook.volatility());
//         console.log("Volatility Expert", volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 400); // 4bps
//         console.log("Swap fee charged (in hundredths of a bip):", fee);
//     }

//     function test_low_vol_mid_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 10 ether;
//         uint248 volatility = 20e18; // 20% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 832); // 8.3bps
//     }

//     function test_low_vol_high_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 100 ether;
//         uint248 volatility = 20e18; // 20% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 2200); // 22bps
//     }

//     //
//     // mid vol tests
//     //
//     function test_mid_vol_low_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 1 ether;
//         uint248 volatility = 60e18; // 60% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 800); // 8bps
//     }

//     function test_mid_vol_mid_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 10 ether;
//         uint248 volatility = 60e18; // 60% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 2097); // 20.9bps
//     }

//     function test_mid_vol_high_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 100 ether;
//         uint248 volatility = 60e18; // 60% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 6200); // 62bps
//     }

//     //
//     // mid vol tests
//     //
//     function test_high_vol_low_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 1 ether;
//         uint248 volatility = 120e18; // 120% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 1400); // 14bps
//     }

//     function test_high_vol_mid_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 10 ether;
//         uint248 volatility = 120e18; // 120% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 3994); // 39.9bps
//     }

//     function test_high_vol_high_amt() public {
//         // Arrange
//         uint256 balance1Before = currency1.balanceOfSelf();
//         bool zeroForOne = true;
//         int256 amountSpecified = 100 ether;
//         uint248 volatility = 120e18; // 120% vol

//         // simulate Brevis service callback update
//         brevisProofMock.setMockOutput(bytes32(0), keccak256(abi.encodePacked(volatility)), VK_HASH);
//         hook.brevisCallback(bytes32(0), abi.encodePacked(volatility));

//         assertEq(hook.volatility(), volatility);

//         // Act
//         uint24 fee = hook.getFee(amountSpecified);
//         BalanceDelta swapDelta = Deployers.swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

//         // Assert
//         // the swap fee is represented in hundredths of a bip, so the 1000000 is 100%
//         assertEq(fee, 12200); // 1.22%
//     }
}