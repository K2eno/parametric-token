// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/tenure/Storage.sol";
import "../src/tenure/Core.sol";
import "../src/tenure/Tenure.sol";
import "../src/tenure/Router.sol";
import "../src/tenure/TenureEngine.sol";
import "../src/interfaces/ITenureToken.sol";

contract TenureDeploy is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        console.log("Deploying with admin:", admin);

        // Logic contracts
        vm.broadcast(adminPrivateKey);
        Core core = new Core();

        vm.broadcast(adminPrivateKey);
        Tenure tenure = new Tenure();

        console.log("Core address:", address(core));
        console.log("Tenure logic address:", address(tenure));

        // Router – no permissions
        vm.broadcast(adminPrivateKey);
        Router router = new Router(
            address(core),
            address(tenure),
            "TenureToken",
            "TEN"
        );

        console.log("Router address:", address(router));

        // Engine
        uint64 rewardsRateBps = 100;
        vm.broadcast(adminPrivateKey);
        TenureEngine engine = new TenureEngine(address(router), rewardsRateBps);

        console.log("Engine address:", address(engine));

        // Set engine
        vm.broadcast(adminPrivateKey);
        ITenureToken(address(router)).setEngine(address(engine));

        // JSON output
        string memory json = string(
            abi.encodePacked(
                '{"router":"',
                vm.toString(address(router)),
                '",',
                '"core":"',
                vm.toString(address(core)),
                '",',
                '"tenureLogic":"',
                vm.toString(address(tenure)),
                '",',
                '"engine":"',
                vm.toString(address(engine)),
                '"}'
            )
        );

        vm.writeFile(
            string.concat(
                vm.projectRoot(),
                "/out/tenure_deployed_addresses.json"
            ),
            json
        );

        console.log("Deployment complete. Addresses saved.");
    }
}
