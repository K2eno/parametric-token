// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/prediction/Storage.sol";
import "../src/prediction/Core.sol";
import "../src/prediction/Permissions.sol";
import "../src/prediction/Prediction.sol";
import "../src/prediction/Router.sol";
import "../src/prediction/PredictionEngine.sol";
import "../src/interfaces/IPredictionToken.sol";

contract PredictionDeploy is Script {
    function run() external {
        // Admin private key (Anvil default account 0)
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        console.log("Deploying with admin:", admin);

        // Deploy logic contracts
        vm.broadcast(adminPrivateKey);
        Core core = new Core();

        vm.broadcast(adminPrivateKey);
        Permissions permissions = new Permissions();

        vm.broadcast(adminPrivateKey);
        Prediction prediction = new Prediction();

        console.log("===== LOGIC CONTRACTS DEPLOYED =====");
        console.log("Core address:", address(core));
        console.log("Permissions address:", address(permissions));
        console.log("Prediction address:", address(prediction));

        // Deploy Router
        string memory name = "PredictionToken";
        string memory symbol = "PRED";

        vm.broadcast(adminPrivateKey);
        Router router = new Router(
            address(core),
            address(permissions),
            address(prediction),
            name,
            symbol
        );

        console.log("===== ROUTER DEPLOYED =====");
        console.log("Router address:", address(router));

        // Deploy Engine
        uint64 startPrice = 73500e8; // 73500 USD

        vm.broadcast(adminPrivateKey);
        PredictionEngine engine = new PredictionEngine(
            address(router),
            startPrice
        );

        console.log("===== ENGINE DEPLOYED =====");
        console.log("Engine address:", address(engine));

        vm.startBroadcast(adminPrivateKey);

        // Set engine on the token (via Router)
        IPredictionToken(address(router)).setEngine(address(engine));
        engine.setupToken();

        // Transfer ownership to admin
        router.transferOwnership(admin);
        engine.transferOwnership(admin);

        vm.stopBroadcast();

        string memory jsonPart1 = string.concat(
            '{"router":"',
            vm.toString(address(router)),
            '",',
            '"core":"',
            vm.toString(address(core)),
            '",',
            '"permissions":"',
            vm.toString(address(permissions)),
            '",'
        );

        string memory jsonPart2 = string.concat(
            '"prediction":"',
            vm.toString(address(prediction)),
            '",',
            '"engine":"',
            vm.toString(address(engine)),
            '",',
            '"admin":"',
            vm.toString(admin),
            '"}'
        );

        // Save deployment addresses
        string memory json = string.concat(jsonPart1, jsonPart2);

        vm.writeFile(
            string.concat(
                vm.projectRoot(),
                "/out/prediction_deployed_addresses.json"
            ),
            json
        );
    }
}
