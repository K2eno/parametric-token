// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../src/mock/AssetToken.sol";
import "../../src/bundle/BundleToken.sol";
import "../../src/bundle/BundleEngine.sol";

contract BundleDeploy is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        console.log("Deploying with admin:", admin);

        // 1. Deploy WBTC (mock)
        vm.broadcast(adminPrivateKey);
        AssetToken wbtc = new AssetToken("Wrapped Bitcoin", "WBTC", 1);

        // 2. Deploy INV (mock)
        vm.broadcast(adminPrivateKey);
        AssetToken inv = new AssetToken("Inverse Token", "INV", 5000);

        // 3. Deploy BundleToken
        vm.broadcast(adminPrivateKey);
        BundleToken bundle = new BundleToken("Bundle Token", "BUN");

        // 4. Deploy BundleEngine with initial price (e.g., 60000 USD with 8 decimals)
        uint64 initialPrice = 67800e8;
        vm.broadcast(adminPrivateKey);
        BundleEngine engine = new BundleEngine(
            address(bundle),
            address(wbtc),
            address(inv),
            initialPrice
        );

        // 5. Set engine in BundleToken
        vm.broadcast(adminPrivateKey);
        bundle.setEngine(address(engine));

        console.log("===== ALL CONTRACTS DEPLOYED =====");
        console.log("WBTC:", address(wbtc));
        console.log("INV:", address(inv));
        console.log("BundleToken:", address(bundle));
        console.log("BundleEngine:", address(engine));

        // Save addresses
        string memory json = string(
            abi.encodePacked(
                '{"wbtc":"',
                vm.toString(address(wbtc)),
                '",',
                '"inv":"',
                vm.toString(address(inv)),
                '",',
                '"bundleToken":"',
                vm.toString(address(bundle)),
                '",',
                '"bundleEngine":"',
                vm.toString(address(engine)),
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
    }
}
