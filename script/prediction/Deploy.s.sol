// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../src/prediction/PredictionToken.sol";
import "../../src/prediction/PredictionEngine.sol";

contract PredictionDeploy is Script {
    function run() external {
        // Admin private key (Anvil default account 0)
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        console.log("Deploying with admin:", admin);

        vm.broadcast(adminPrivateKey);
        PredictionToken token = new PredictionToken("PredictionToken", "PRED");

        uint64 startPrice = 73500e8; // 73500 USD

        vm.startBroadcast(adminPrivateKey);
        PredictionEngine engine = new PredictionEngine(
            address(token),
            startPrice
        );

        console.log("===== ALL CONTRACTS DEPLOYED =====");
        console.log("Token address:", address(token));
        console.log("Engine address:", address(engine));

        token.setEngine(address(engine));
        engine.setupToken();

        string memory json = string(
            abi.encodePacked(
                '{"predictionToken":"',
                vm.toString(address(token)),
                '",',
                '"predictionEngine":"',
                vm.toString(address(engine)),
                '"}'
            )
        );

        vm.writeFile(
            string.concat(
                vm.projectRoot(),
                "/out/prediction_deployed_addresses.json"
            ),
            json
        );

        vm.stopBroadcast();
    }
}
