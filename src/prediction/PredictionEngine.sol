// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IPredictionToken.sol";
import "../interfaces/IPredictionEngine.sol";

contract PredictionEngine is Ownable, IPredictionEngine {
    // ====== CONSTANTS ======

    uint256 public constant ROUND_POINTS = 1000e18; // 1000 USDT equivalent
    uint64 public constant MAX_ROUNDS = 5;
    uint64 public constant MIN_DIFF = 10e8;
    uint64 public constant ROUND_DURATION = 3600;

    // ====== STRUCTS ======

    // Prediction weights
    struct Weight {
        uint256 weight;
        bool claimed;
    }

    // Round data
    struct RoundData {
        uint64 range;
        uint64 assetPrice;
        uint64 resolutionTime;
        Status status;
        uint256 totalWeight;
        mapping(address => mapping(uint48 => Weight)) weights; // trader => subId => Weight(weight, claimed)
        mapping(address => uint256) pointsEarned;
    }

    // ====== STATE ======

    IPredictionToken private _token;

    uint64 private _startPrice;
    mapping(uint64 => RoundData) private _rounds;

    // ====== MODIFIERS ======

    modifier onlyValidForClosing(uint64 round) {
        require(round < MAX_ROUNDS, "Invalid round");
        require(
            block.timestamp > _rounds[round].resolutionTime,
            "Round has not ended"
        );
        _;
    }

    modifier onlyActive(uint64 round) {
        require(_rounds[round].status == Status.Active, "Not active status");
        _;
    }

    modifier onlyReporting(uint64 round) {
        require(
            _rounds[round].status == Status.Reporting,
            "Not reporting status"
        );
        _;
    }

    modifier onlyClaiming(uint64 round) {
        require(
            _rounds[round].status == Status.Claiming,
            "Not claiming status"
        );
        _;
    }

    // ====== CONSTRUCTOR ======

    constructor(address token, uint64 startPrice_) Ownable(msg.sender) {
        require(token != address(0), "Zero token");
        _token = IPredictionToken(token);
        _startPrice = startPrice_;

        uint64 startTime = uint64(
            (block.timestamp / ROUND_DURATION) * ROUND_DURATION
        );
        for (uint64 i = 0; i < MAX_ROUNDS; i++) {
            _rounds[i].status = Status.Active;
            _rounds[i].resolutionTime = startTime + i * ROUND_DURATION;
        }
    }

    function setupToken() external onlyOwner {
        _token.setMaxRounds(MAX_ROUNDS);
    }

    // ====== FUNCTIONS ======

    // Admin functions
    function closeRound(
        uint64 round,
        uint64 range
    ) external onlyOwner onlyValidForClosing(round) onlyActive(round) {
        require(range > MIN_DIFF, "Invalid range");
        _rounds[round].range = range;
        uint64 minPrice = _startPrice - range / 2;

        // Generate pseudo‑random number using block data
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, round)
            )
        );

        _rounds[round].assetPrice = uint64((random % range) + minPrice);
        _rounds[round].status = Status.Reporting;
        emit RoundClosed(
            round,
            _rounds[round].range,
            _rounds[round].assetPrice
        );
    }

    function closeReporting(
        uint64 round
    ) external onlyOwner onlyValidForClosing(round) onlyReporting(round) {
        RoundData storage data = _rounds[round];
        require(data.totalWeight > 0, "No weights recorded");

        _rounds[round].status = Status.Claiming;
        emit ReportingClosed(round, data.totalWeight);
    }

    // Trader functions
    function report(uint64 round, uint48 subId) external onlyReporting(round) {
        address trader = msg.sender;
        RoundData storage data = _rounds[round];

        // Check that trader has positive balance in that sub-account for this round
        uint256 balance = _token.parametricBalanceOf(trader, subId);
        require(balance > 0, "Zero token balance");
        require(
            data.weights[trader][subId].weight == 0,
            "Token was already reported"
        );
        require(
            _token.parameterOf(1, trader, subId) == round,
            "Token has a different round"
        );

        // Get prediction price from token
        uint64 predictionPrice = _token.parameterOf(0, trader, subId);

        // Get asset price
        uint256 resolutionPrice = data.assetPrice;

        // Compute weight = range / |predictionPrice - assetPrice|
        uint256 diff =
            predictionPrice > resolutionPrice
                ? predictionPrice - resolutionPrice
                : resolutionPrice - predictionPrice;
        if (diff < MIN_DIFF) diff = MIN_DIFF;

        uint256 normalizedBalance =
            _token.parametricBalanceOf(trader, subId) / 1e10;
        uint256 w = (data.range * normalizedBalance) / diff;

        // Store weight for this trader/subId
        data.weights[trader][subId].weight = w;
        data.totalWeight += w;

        _token.burn(trader, subId, balance);

        emit TokenReportedAndBurned(trader, subId, round, balance, w);
    }

    function claim(
        uint64 round,
        uint48 subId
    ) external onlyValidForClosing(round) onlyClaiming(round) {
        address trader = msg.sender;
        require(!_rounds[round].weights[trader][subId].claimed);
        uint256 points =
            (ROUND_POINTS * _rounds[round].weights[trader][subId].weight) /
                _rounds[round].totalWeight;
        _rounds[round].weights[trader][subId].claimed = true;
        _rounds[round].pointsEarned[trader] += points;
        emit PointsDistributed(trader, subId, round, points);
    }

    // ====== GETTERS ======

    function startPrice() external view returns (uint64) {
        return _startPrice;
    }
    function weight(
        uint64 round,
        address account,
        uint48 subId
    ) external view returns (uint256) {
        return _rounds[round].weights[account][subId].weight;
    }

    function totalWeight(uint64 round) external view returns (uint256) {
        return _rounds[round].totalWeight;
    }

    function assetPrice(uint64 round) external view returns (uint64) {
        return _rounds[round].assetPrice;
    }

    function roundStatus(uint64 round) external view returns (Status) {
        return _rounds[round].status;
    }

    function pointsEarned(
        uint64 round,
        address account
    ) external view returns (uint256) {
        return _rounds[round].pointsEarned[account];
    }
}
