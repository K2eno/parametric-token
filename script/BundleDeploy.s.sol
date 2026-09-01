// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/bundle/Storage.sol";
import "../src/bundle/Core.sol";
import "../src/bundle/Bundle.sol";
import "../src/bundle/Router.sol";
import "../src/bundle/BundleEngine.sol";
import "../src/interfaces/IBundleToken.sol";
import "../src/mock/AssetToken.sol";

contract BundleDeploy is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        console.log("Deploying with admin:", admin);

        // Mock tokens
        vm.broadcast(adminPrivateKey);
        AssetToken wbtc = new AssetToken("WBTC", "WBTC", 2);
        AssetToken inv = new AssetToken("INV", "INV", 100_000);

        console.log("WBTC address:", address(wbtc));
        console.log("INV address:", address(inv));

        // Logic contracts
        vm.broadcast(adminPrivateKey);
        Core core = new Core();

        vm.broadcast(adminPrivateKey);
        Bundle bundle = new Bundle();

        console.log("Core address:", address(core));
        console.log("Bundle logic address:", address(bundle));

        // Router – no permissions
        vm.broadcast(adminPrivateKey);
        Router router = new Router(
            address(core),
            address(bundle),
            "BundleToken",
            "BUN"
        );

        console.log("Router address:", address(router));

        // Engine
        uint64 initialPrice = 73000e8;
        vm.broadcast(adminPrivateKey);
        BundleEngine engine = new BundleEngine(
            address(router),
            address(wbtc),
            address(inv),
            initialPrice
        );

        console.log("Engine address:", address(engine));

        // Set engine
        vm.broadcast(adminPrivateKey);
        IBundleToken(address(router)).setEngine(address(engine));

        // JSON output
        string memory json = string(
            abi.encodePacked(
                '{"router":"',
                vm.toString(address(router)),
                '",',
                '"core":"',
                vm.toString(address(core)),
                '",',
                '"bundle":"',
                vm.toString(address(bundle)),
                '",',
                '"engine":"',
                vm.toString(address(engine)),
                '",',
                '"wbtc":"',
                vm.toString(address(wbtc)),
                '",',
                '"inv":"',
                vm.toString(address(inv)),
                '"}'
            )
        );

        vm.writeFile(
            string.concat(
                vm.projectRoot(),
                "/out/bundle_deployed_addresses.json"
            ),
            json
        );

        console.log("Deployment complete. Addresses saved.");
    }
}
