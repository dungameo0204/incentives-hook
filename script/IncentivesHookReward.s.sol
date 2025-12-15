// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/test/PoolClaimsTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {HookMiner} from "../test/HookMiner.sol";
import {IncentivesHook} from "../src/IncentivesHook.sol";
import {MockBrevisProof} from "../src/brevis/MockBrevisProof.sol";
import "forge-std/console.sol";

contract IncentivesHookRewardScript is Script {
    // ======== ĐỊA CHỈ CÓ SẴN ========
    PoolManager manager =
        PoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    PoolSwapTest swapRouter =
        PoolSwapTest(0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe);
    PoolModifyLiquidityTest modifyLiquidityRouter =
        PoolModifyLiquidityTest(0x0C478023803a644c94c4CE1C1e7b9A087e411B0A);
    address constant MODIFY_LIQUIDITY_ROUTER =
        address(0x0C478023803a644c94c4CE1C1e7b9A087e411B0A);
    address constant SWAP_ROUTER =
        address(0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe);

    // Hook đã deploy
    IncentivesHook hook =
        IncentivesHook(0x5F7CcAE2A24eB9da8BAC46217c9910F3C442ffc0);

    address hookAddress = address(hook);

    // Token đã deploy từ script trước
    Currency token0 = Currency.wrap(0x8c50C847524531fF288Fb7bBF9882e55dA881a30);
    Currency token1 = Currency.wrap(0xE18069fAac066353b8706cEEEB711aA7c4340a75);
    MockERC20 tokenA = MockERC20(0x8c50C847524531fF288Fb7bBF9882e55dA881a30);
    MockERC20 tokenB = MockERC20(0xE18069fAac066353b8706cEEEB711aA7c4340a75);
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    PoolKey key;

    function run() public {
        int24 activeLower = -120;
        int24 activeUpper = 120;

        int24 unactiveLower = -540;
        int24 unactiveUpper = -480;
        
        bytes32 saltlp1 = bytes32(keccak256(abi.encode("lp1")));
        bytes32 saltlp2 = bytes32(keccak256(abi.encode("lp2")));
        vm.startBroadcast();

        console.log("=== Starting mint token ===");

        tokenA.mint(msg.sender, 1000000000000000000000 ether);
        tokenB.mint(msg.sender, 1000000000000000000000 ether);

        tokenA.approve(MODIFY_LIQUIDITY_ROUTER, 100000000 ether);
        tokenB.approve(MODIFY_LIQUIDITY_ROUTER, 100000000 ether);
        tokenA.approve(SWAP_ROUTER, 100000000 ether);
        tokenB.approve(SWAP_ROUTER, 100000000 ether);


        console.log("TokenA balance:", tokenA.balanceOf(msg.sender));
        console.log("TokenB balance:", tokenB.balanceOf(msg.sender));
        console.log("TokenA balance:", tokenA.balanceOf(MODIFY_LIQUIDITY_ROUTER));
        console.log("TokenB balance:", tokenB.balanceOf(MODIFY_LIQUIDITY_ROUTER));



        vm.sleep(5);
        key = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddress)
        });
        console.log("Pool Key created.");

        console.log("=== Adding liquidity from Lp0 ===");
         modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000 ether,
                salt: 0
            }),
            new bytes(0)
        );

        console.log("Lp0 added liquidity in active range.");

       console.log("=== Adding liquidity from Lp1 ===");

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(
                activeLower,
                activeUpper,
                1000 ether,
                saltlp1
            ),
            new bytes(0)
        );

        console.log("LP1 added liquidity in active range.");

        console.log("=== Adding liquidity from Lp2 ===");
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(
                unactiveLower,
                unactiveUpper,
                1000 ether,
                saltlp2
            ),
            new bytes(0)
        );

        console.log("LP2 added liquidity in unactive range.");

        console.log("=== Some user swap ===");
    
        swapRouter.swap(
            key,
            SwapParams(true, 10 ether, MIN_SQRT_PRICE + 1),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            new bytes(0)
        );

        vm.sleep(5);
        

        uint256 rewardLP1 = hook.earned(
            key,
            activeLower,
            activeUpper,
            MODIFY_LIQUIDITY_ROUTER,
            saltlp1
        );
        uint256 rewardLP2 = hook.earned(
            key,
            unactiveLower,
            unactiveUpper,
            MODIFY_LIQUIDITY_ROUTER,
            saltlp2
        );

        console.log("Reward LP1:", rewardLP1);
        console.log("Reward LP2:", rewardLP2);
    }
}
