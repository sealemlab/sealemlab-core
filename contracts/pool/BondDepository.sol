// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tool/interface/IPancakePair.sol";

/**
 * @title Bond Depository
 * @author SEALEM-LAB
 * @notice Contract to supply Bond
 */
contract BondDepository is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    address public stlpAddr;
    uint256 public stPrice;

    uint256 public bondCount;
    mapping(uint256 => address) public lpAddr;
    mapping(uint256 => address) public receivingAddr;
    mapping(uint256 => uint256) public bondMaxSupplyLp;
    mapping(uint256 => uint256) public bondRate;
    mapping(uint256 => uint256) public bondTerm;
    mapping(uint256 => uint256) public bondConclusion;

    mapping(uint256 => uint256) public lpPrice;
    mapping(uint256 => uint256) public bondSoldLpAmount;

    mapping(address => uint256) public userOrderCount;
    mapping(address => mapping(uint256 => uint256)) public userOrderBondId;
    mapping(address => mapping(uint256 => uint256)) public userOrderLpAmount;
    mapping(address => mapping(uint256 => uint256)) public userOrderUsdPayout;
    mapping(address => mapping(uint256 => uint256)) public userOrderExpiry;
    mapping(address => mapping(uint256 => uint256)) public userOrderClaimTime;

    event SetSTLP(address stlpAddr);
    event Bond(
        address indexed user,
        uint256 bondId,
        uint256 lpAmount,
        uint256 lpPrice,
        uint256 usdPayout,
        uint256 expiry
    );
    event Claim(
        address indexed user,
        uint256[] orderIds,
        uint256 usdPayout,
        uint256 stPrice,
        uint256 stPayout
    );

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set ST LP Address
     */
    function setSTLP(address _stlpAddr) external onlyRole(MANAGER_ROLE) {
        stlpAddr = _stlpAddr;

        emit SetSTLP(_stlpAddr);
    }

    /**
     * @dev Bond
     */
    function bond(uint256 bondId, uint256 lpAmount) external nonReentrant {
        require(lpAmount > 0, "LP Amount must > 0");
        require(
            getBondLeftSupplyLp(bondId) >= lpAmount,
            "Not enough bond LP supply"
        );
        require(
            receivingAddr[bondId] != address(0),
            "The receiving address of this bond has not been set"
        );
        require(block.timestamp < bondConclusion[bondId], "Bond concluded");

        updateLpPrice(bondId);

        IERC20(lpAddr[bondId]).safeTransferFrom(
            msg.sender,
            receivingAddr[bondId],
            lpAmount
        );

        uint256 expiry = bondTerm[bondId] + block.timestamp;
        uint256 usdPayout = (lpPrice[bondId] * lpAmount * bondRate[bondId]) /
            1e18 /
            1e4;

        userOrderBondId[msg.sender][userOrderCount[msg.sender]] = bondId;
        userOrderLpAmount[msg.sender][userOrderCount[msg.sender]] = lpAmount;
        userOrderUsdPayout[msg.sender][userOrderCount[msg.sender]] = usdPayout;
        userOrderExpiry[msg.sender][userOrderCount[msg.sender]] = expiry;
        userOrderCount[msg.sender]++;

        bondSoldLpAmount[bondId] += lpAmount;

        emit Bond(
            msg.sender,
            bondId,
            lpAmount,
            lpPrice[bondId],
            usdPayout,
            expiry
        );
    }

    /**
     * @dev Claim
     */
    function claim(uint256[] memory orderIds) external nonReentrant {
        updateStPrice();

        uint256 usdPayout;
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (
                block.timestamp >= userOrderExpiry[msg.sender][orderIds[i]] &&
                userOrderClaimTime[msg.sender][orderIds[i]] == 0
            ) {
                userOrderClaimTime[msg.sender][orderIds[i]] = block.timestamp;
                usdPayout += userOrderUsdPayout[msg.sender][orderIds[i]];
            }
        }

        uint256 stPayout = (usdPayout * 1e18) / stPrice;

        IERC20(IPancakePair(stlpAddr).token0()).safeTransfer(
            msg.sender,
            stPayout
        );

        emit Claim(msg.sender, orderIds, usdPayout, stPrice, stPayout);
    }

    /**
     * @dev Update Lp Price
     */
    function updateLpPrice(uint256 bondId) public {
        (, uint112 reserve1, ) = IPancakePair(lpAddr[bondId]).getReserves();
        lpPrice[bondId] =
            (2 * reserve1 * 1e18) /
            IPancakePair(lpAddr[bondId]).totalSupply();
    }

    /**
     * @dev Update ST Price
     */
    function updateStPrice() public {
        (uint112 reserve0, uint112 reserve1, ) = IPancakePair(stlpAddr)
            .getReserves();
        stPrice = (reserve1 * 1e18) / reserve0;
    }

    /**
     * @dev Get Bond Left Supply LP
     */
    function getBondLeftSupplyLp(uint256 bondId) public view returns (uint256) {
        return bondMaxSupplyLp[bondId] - bondSoldLpAmount[bondId];
    }
}
