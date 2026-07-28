// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../src/tenure/TenureToken.sol";
import "../../src/tenure/TenureEngine.sol";

contract TenureDeploy is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        console.log("Deploying with admin:", admin);

        vm.broadcast(adminPrivateKey);
        TenureToken token = new TenureToken("Tenure Token", "TEN");

        // Set rewards rate: 100 bps = 1% per month (rewards base = 30 days)
        uint64 rewardsRateBps = 100;

        vm.broadcast(adminPrivateKey);
        TenureEngine engine = new TenureEngine(address(token), rewardsRateBps);

        console.log("===== ALL CONTRACTS DEPLOYED =====");
        console.log("Token address:", address(token));
        console.log("Engine address:", address(engine));

        // Set engine on token so it can mint/burn
        vm.broadcast(adminPrivateKey);
        token.setEngine(address(engine));

        string memory json = string(
            abi.encodePacked(
                '{"tenureToken":"',
                vm.toString(address(token)),
                '",',
                '"tenureEngine":"',
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
    }
}
