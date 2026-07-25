// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPredictionEngine {
    enum Status {
        Active,
        Reporting,
        Claiming
    }

    event RoundClosed(uint64 indexed round, uint64 range, uint64 assetPrice);
    event ReportingClosed(uint64 indexed round, uint256 totalWeight);
    event TokenReportedAndBurned(
        address indexed trader,
        uint48 indexed subId,
        uint64 indexed round,
        uint256 amount,
        uint256 weight
    );
    event PointsDistributed(
        address indexed trader,
        uint48 indexed subId,
        uint64 indexed round,
        uint256 points
    );

    // Admin functions
    function closeRound(uint64 round, uint64 range) external;
    function closeReporting(uint64 round) external;

    // Trader functions
    function report(uint64 round, uint48 subId) external;
    function claim(uint64 round, uint48 subId) external;

    // View functions
    function getStartPrice() external view returns (uint64);
    function getWeight(
        uint64 round,
        address trader,
        uint48 subId
    ) external view returns (uint256);
    function getTotalWeight(uint64 round) external view returns (uint256);
    function getAssetPrice(uint64 round) external view returns (uint64);
    function getRoundStatus(uint64 round) external view returns (Status);
    function getPointsEarned(
        uint64 round,
        address trader
    ) external view returns (uint256);
}
