source .env
#forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast --verify 
#forge script script/HookMiningSample.s.sol:HookMiningSample --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast --verify
#forge script script/V4PreDeployed.s.sol:V4PreDeployed --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast --legacy --gas-price 2000000000 --slow
forge script script/DeployIncentivesHook.s.sol:DeployIncentivesHook --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast --legacy --gas-price 2000000000 --slow  --verify
#forge test --match-path test/IncentivesHook.t.sol -vvvv
#forge script script/IncentivesHookReward.s.sol:IncentivesHookRewardScript --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast --legacy --gas-price 2000000000 --slow
#forge test --match-path test/IncentivesHook.t.sol --match-test test_RewardDistribution -vvvv
#forge test --match-test test_RewardDebt_Fix -vv
#forge test --match-test test_RemoveLiquidity_And_Claim -vvvv
#forge script script/logpoolid.s.sol:CalculatePoolId
#forge script script/DeployReader.s.sol --rpc-url $SEPOLIA_CHAIN --private-key $PRIVATE_KEY --broadcast