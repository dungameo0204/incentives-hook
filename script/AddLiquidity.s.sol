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

contract AddLiquidity is Script {
    // ======== ĐỊA CHỈ CÓ SẴN ========
    address constant MODIFY_LIQUIDITY_ROUTER = address(0x0C478023803a644c94c4CE1C1e7b9A087e411B0A);
    address constant SWAP_ROUTER = address(0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe);
    address constant MANAGER_ADDRESS = address(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    PoolSwapTest swapRouter = PoolSwapTest(SWAP_ROUTER);
    PoolModifyLiquidityTest modifyLiquidityRouter = PoolModifyLiquidityTest(MODIFY_LIQUIDITY_ROUTER);
    PoolManager manager = PoolManager(MANAGER_ADDRESS);

    // Hook đã deploy
    address hookAddress = address(0xF410281312b887d6dCd117bF9be8E1A11E087fC0);
    IncentivesHook hook = IncentivesHook(hookAddress);

    // Token đã deploy từ script trước
    Currency token0 = Currency.wrap(0xA7a1a88e6f591Bf05D31d09BaFCE85ab6d294139);
    Currency token1 = Currency.wrap(0xD8d97fe5792e6A62D1F66501A4641556f50e0599);
    MockERC20 tokenA = MockERC20(0xA7a1a88e6f591Bf05D31d09BaFCE85ab6d294139);
    MockERC20 tokenB = MockERC20(0xD8d97fe5792e6A62D1F66501A4641556f50e0599);
    uint160 internal constant MIN_SQRT_PRICE = 4295128739;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    PoolKey key;

    function run() public {

        bytes32 saltlp1 = bytes32(keccak256(abi.encode("lp1")));
        bytes32 saltlp2 = bytes32(keccak256(abi.encode("lp2")));

        console.logBytes32(saltlp1);
        console.logBytes32(saltlp2);
        key = PoolKey({currency0: token0, currency1: token1, fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddress)});
        console.log("Pool Key created.");

        vm.startBroadcast();
        
       

        console.log("=== Adding liquidity from Lp0 ===");
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1000 ether, salt: 0}),
            new bytes(0)
        );
        console.log("Lp0 added liquidity in active range.");      
    }
}
