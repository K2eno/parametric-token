// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPredictionEngine {
    // ====== CONSTANTS ======

    enum Status {
        Active,
        Reporting,
        Claiming
    }

    // ====== EVENTS ======

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

    // ====== FUNCTIONS ======

    // Admin functions
    function closeRound(uint64 round, uint64 range) external;
    function closeReporting(uint64 round) external;

    // Trader functions
    function report(uint64 round, uint48 subId) external;
    function claim(uint64 round, uint48 subId) external;

    // ====== GETTERS ======

    function startPrice() external view returns (uint64);
    function weight(
        uint64 round,
        address trader,
        uint48 subId
    ) external view returns (uint256);
    function totalWeight(uint64 round) external view returns (uint256);
    function assetPrice(uint64 round) external view returns (uint64);
    function roundStatus(uint64 round) external view returns (Status);
    function pointsEarned(
        uint64 round,
        address trader
    ) external view returns (uint256);
}
