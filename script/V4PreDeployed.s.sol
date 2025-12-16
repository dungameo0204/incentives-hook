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
import {BasicHook} from "../src/BasicHook.sol";
import "forge-std/console2.sol";

contract V4PreDeployed is Script {
    PoolManager manager = PoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
    PoolSwapTest swapRouter = PoolSwapTest(0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe);
    PoolModifyLiquidityTest modifyLiquidityRouter = PoolModifyLiquidityTest(0x0C478023803a644c94c4CE1C1e7b9A087e411B0A);

    Currency token0;
    Currency token1;

    PoolKey key;

    function setUp() public {
        vm.startBroadcast();

        console2.log("=== Deploying tokens ===");

        MockERC20 tokenA = new MockERC20("Token0", "TK0", 18);
        MockERC20 tokenB = new MockERC20("Token1", "TK1", 18);

        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));

        vm.sleep(5);

        // sort tokens
        if (address(tokenA) > address(tokenB)) {
            token0 = Currency.wrap(address(tokenB));
            token1 = Currency.wrap(address(tokenA));
        } else {
            token0 = Currency.wrap(address(tokenA));
            token1 = Currency.wrap(address(tokenB));
        }

        console2.log("Token0 (sorted):", Currency.unwrap(token0));
        console2.log("Token1 (sorted):", Currency.unwrap(token1));

        vm.sleep(5);

        console2.log("Approving routers...");
        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);

        vm.sleep(5);

        console2.log("Minting tokens...");
        tokenA.mint(msg.sender, 100 ether);
        tokenB.mint(msg.sender, 100 ether);

        console2.log("TokenA balance:", tokenA.balanceOf(msg.sender));
        console2.log("TokenB balance:", tokenB.balanceOf(msg.sender));

        //deploy hook
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BasicHook).creationCode, abi.encode(address(manager)));

        BasicHook hook = new BasicHook{salt: salt}(manager);
        require(address(hook) == hookAddress, "hook address mismatch");

        console2.log("Hook deployed at:");
        console2.logAddress(hookAddress);

        key = PoolKey({currency0: token0, currency1: token1, fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddress)});

        console2.log("==============================");
        console2.log("PoolManager:", address(manager));
        console2.log("Hook:", address(key.hooks));
        console2.log("Fee:", key.fee);
        console2.log("TickSpacing:", key.tickSpacing);
        console2.log("==============================");

        vm.sleep(5);

        console2.log("Initializing pool...");
        manager.initialize(key, 79228162514264337593543950336);

        console2.log("Pool initialized!");
    }

    function run() public {
        vm.sleep(5);

        // compute poolId
        bytes32 poolId = keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks));

        console2.log("Pool ID:");
        console2.logBytes32(poolId);

        console2.log("Adding liquidity...");

        modifyLiquidityRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 10e18, salt: 0}), new bytes(0)
        );

        console2.log("Liquidity added!");
    }
}
