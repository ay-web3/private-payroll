
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
  function transfer(address to, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function balanceOf(address a) external view returns (uint256);
}

contract PayrollVault {
  struct Employee {
    bool active;
    uint8 tier;          // 0..N-1
    uint64 lastPaidAt;   // unix timestamp
  }

  address public owner;
  IERC20 public immutable payToken;

  uint64 public payCycleSeconds; // e.g. 30 days
  uint256[] public tierAmounts;  // tier -> amount (in token decimals)

  mapping(address => Employee) public employees;

  event Funded(address indexed from, uint256 amount);
  event EmployeeAdded(address indexed employee, uint8 tier);
  event EmployeeUpdated(address indexed employee, bool active, uint8 tier);
  event Paid(address indexed employee, uint256 amount, uint64 paidAt);

  modifier onlyOwner() {
    require(msg.sender == owner, "NOT_OWNER");
    _;
  }

  constructor(
    address _token,
    uint64 _payCycleSeconds,
    uint256[] memory _tierAmounts
  ) {
    require(_token != address(0), "BAD_TOKEN");
    require(_payCycleSeconds >= 1 days, "CYCLE_TOO_SMALL");
    require(_tierAmounts.length > 0, "NO_TIERS");

    owner = msg.sender;
    payToken = IERC20(_token);
    payCycleSeconds = _payCycleSeconds;
    tierAmounts = _tierAmounts;
  }

  function setEmployee(
    address employee,
    bool active,
    uint8 tier
  ) external onlyOwner {
    require(employee != address(0), "BAD_EMP");
    require(tier < tierAmounts.length, "BAD_TIER");

    Employee storage e = employees[employee];

    // first time add
    if (e.lastPaidAt == 0 && e.active == false && e.tier == 0) {
      // new employee, leave lastPaidAt as 0 so they can claim immediately
      emit EmployeeAdded(employee, tier);
    } else {
      emit EmployeeUpdated(employee, active, tier);
    }

    e.active = active;
    e.tier = tier;
  }

  function fund(uint256 amount) external {
    require(amount > 0, "BAD_AMOUNT");
    require(
      payToken.transferFrom(msg.sender, address(this), amount),
      "TRANSFER_FAIL"
    );
    emit Funded(msg.sender, amount);
  }

  function dueAmount(address employee) public view returns (uint256) {
    Employee memory e = employees[employee];
    if (!e.active) return 0;

    uint256 amount = tierAmounts[e.tier];

    // If never paid, allow immediate claim
    if (e.lastPaidAt == 0) return amount;

    // Must wait a full cycle
    if (
      block.timestamp <
      uint256(e.lastPaidAt) + uint256(payCycleSeconds)
    ) return 0;

    return amount;
  }

  function claim() external {
    uint256 amount = dueAmount(msg.sender);
    require(amount > 0, "NOT_DUE");
    require(
      payToken.balanceOf(address(this)) >= amount,
      "INSUFFICIENT_VAULT"
    );

    employees[msg.sender].lastPaidAt = uint64(block.timestamp);

    require(
      payToken.transfer(msg.sender, amount),
      "PAY_FAIL"
    );

    emit Paid(msg.sender, amount, uint64(block.timestamp));
  }

  function vaultBalance() external view returns (uint256) {
    return payToken.balanceOf(address(this));
  }

  function tiersCount() external view returns (uint256) {
    return tierAmounts.length;
  }
}

