// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./libraries/NativeAssets.sol";

// HonToken with Governance.
contract HonToken is Ownable, ERC20Burnable {
  // Avalanche X-chain address
  uint256 private _assetID;

  // Fixed cap token
  uint256 private immutable maxSupply;
  // Keep track of burned tokens
  uint256 public burnedTokens;

  address public treasuryAddress;
  address public gameRewardAddress;

  /// @dev Hon Token
  constructor(
    uint256 _maxSupply,
    address _treasuryAddress,
    address _gameRewardAddress,
    uint256 assetID_
  ) ERC20("HonToken", "HON") {
    maxSupply = _maxSupply;
    treasuryAddress = _treasuryAddress;
    gameRewardAddress = _gameRewardAddress;
    _assetID = assetID_;
  }

  /// @dev Limit total supply
  modifier limitSupply(uint256 _amount) {
    require(totalSupply() + _amount <= maxSupply, "Max supply has been reached.");
    _;
  }

  /**
   * @dev ARC20 compatibility
   */
  event Deposit(address indexed dst, uint256 value);
  event Withdrawal(address indexed src, uint256 value);

  // ARC20 - Deposit function
  function deposit() public {
    uint256 updatedBalance = NativeAssets.assetBalance(address(this), _assetID);
    // Multiply with 1 gwei to increase decimal count
    uint256 depositAmount = (updatedBalance * 1 gwei) - totalSupply();
    require(depositAmount > 0, "Deposit amount should be more than zero");

    _mint(msg.sender, depositAmount);
    emit Deposit(msg.sender, depositAmount);
  }

  // ARC20 - Withdraw function
  function withdraw(uint256 amount) public {
    require(balanceOf(msg.sender) >= amount, "insufficent funds");
    _burn(msg.sender, amount);
    // Divide by 1 gwei to decrease decimal count
    // Division always floors
    uint256 native_amount = amount / 1 gwei;
    NativeAssets.assetCall(msg.sender, _assetID, native_amount, "");
    emit Withdrawal(msg.sender, amount);
  }

  /**
   * @dev Override ERC20Burnable functions to keep track of burned token amount
   * Cross chain transfers don't effect burn amount
   */
  function burn(uint256 amount) public override {
    super.burn(amount);
    burnedTokens += amount;
  }

  function burnFrom(address account, uint256 amount) public override {
    super.burnFrom(account, amount);
    burnedTokens += amount;
  }

  /**
   * @dev Returns the `assetID` of the underlying asset this contract handles.
   */
  function assetID() external view returns (uint256) {
    return _assetID;
  }

  /**
   * @dev Creates `_amount` token to `_to`.
   * Must only be called by the owner (MasterGamer).
   */
  function mint(address _to, uint256 _amount) public onlyOwner limitSupply(_amount) {
    _mint(_to, _amount);
  }

  /**
   * TODO: 
   * This is just for testing
   */
  function changeAssetID(uint256 assetID_) public onlyOwner {
    _assetID = assetID_;
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////

  // Copied and modified from YAM code:
  // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
  // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
  // Which is copied and modified from COMPOUND:
  // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

  /// @dev A record of each accounts delegate
  mapping(address => address) internal _delegates;

  /// @dev A checkpoint for marking number of votes from a given block
  struct Checkpoint {
    uint32 fromBlock;
    uint256 votes;
  }

  /// @dev A record of votes checkpoints for each account, by index
  mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

  /// @dev The number of checkpoints for each account
  mapping(address => uint32) public numCheckpoints;

  /// @dev The EIP-712 typehash for the contract's domain
  bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

  /// @dev The EIP-712 typehash for the delegation struct used by the contract
  bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

  /// @dev A record of states for signing / validating signatures
  mapping(address => uint256) public nonces;

  /// @dev An event thats emitted when an account changes its delegate
  event DelegateChanged(
    address indexed delegator,
    address indexed fromDelegate,
    address indexed toDelegate
  );

  /// @dev An event thats emitted when a delegate account's vote balance changes
  event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

  /**
   * @dev Delegate votes from `msg.sender` to `delegatee`
   * @param delegator The address to get delegatee for
   */
  function delegates(address delegator) external view returns (address) {
    return _delegates[delegator];
  }

  /**
   * @dev Delegate votes from `msg.sender` to `delegatee`
   * @param delegatee The address to delegate votes to
   */
  function delegate(address delegatee) external {
    return _delegate(msg.sender, delegatee);
  }

  /**
   * @dev Delegates votes from signatory to `delegatee`
   * @param delegatee The address to delegate votes to
   * @param nonce The contract state required to match the signature
   * @param expiry The time at which to expire the signature
   * @param v The recovery byte of the signature
   * @param r Half of the ECDSA signature pair
   * @param s Half of the ECDSA signature pair
   */
  function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 domainSeparator = keccak256(
      abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
    );

    bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));

    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

    address signatory = ecrecover(digest, v, r, s);
    require(signatory != address(0), "HON::delegateBySig: invalid signature");
    require(nonce == nonces[signatory]++, "HON::delegateBySig: invalid nonce");
    require(block.timestamp <= expiry, "HON::delegateBySig: signature expired");
    return _delegate(signatory, delegatee);
  }

  /**
   * @dev Gets the current votes balance for `account`
   * @param account The address to get votes balance
   * @return The number of current votes for `account`
   */
  function getCurrentVotes(address account) external view returns (uint256) {
    uint32 nCheckpoints = numCheckpoints[account];
    return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
  }

  /**
   * @dev Determine the prior number of votes for an account as of a block number
   * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
   * @param account The address of the account to check
   * @param blockNumber The block number to get the vote balance at
   * @return The number of votes the account had as of the given block
   */
  function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
    require(blockNumber < block.number, "HON::getPriorVotes: not yet determined");

    uint32 nCheckpoints = numCheckpoints[account];
    if (nCheckpoints == 0) {
      return 0;
    }

    // First check most recent balance
    if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
      return checkpoints[account][nCheckpoints - 1].votes;
    }

    // Next check implicit zero balance
    if (checkpoints[account][0].fromBlock > blockNumber) {
      return 0;
    }

    uint32 lower = 0;
    uint32 upper = nCheckpoints - 1;
    while (upper > lower) {
      uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
      Checkpoint memory cp = checkpoints[account][center];
      if (cp.fromBlock == blockNumber) {
        return cp.votes;
      } else if (cp.fromBlock < blockNumber) {
        lower = center;
      } else {
        upper = center - 1;
      }
    }
    return checkpoints[account][lower].votes;
  }

  function _delegate(address delegator, address delegatee) internal {
    address currentDelegate = _delegates[delegator];
    uint256 delegatorBalance = balanceOf(delegator); // balance of underlying HONs (not scaled);
    _delegates[delegator] = delegatee;

    emit DelegateChanged(delegator, currentDelegate, delegatee);

    _moveDelegates(currentDelegate, delegatee, delegatorBalance);
  }

  function _moveDelegates(
    address srcRep,
    address dstRep,
    uint256 amount
  ) internal {
    if (srcRep != dstRep && amount > 0) {
      if (srcRep != address(0)) {
        // decrease old representative
        uint32 srcRepNum = numCheckpoints[srcRep];
        uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
        uint256 srcRepNew = srcRepOld - amount;
        _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
      }

      if (dstRep != address(0)) {
        // increase new representative
        uint32 dstRepNum = numCheckpoints[dstRep];
        uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
        uint256 dstRepNew = dstRepOld + amount;
        _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
      }
    }
  }

  function _writeCheckpoint(
    address delegatee,
    uint32 nCheckpoints,
    uint256 oldVotes,
    uint256 newVotes
  ) internal {
    uint32 blockNumber = safe32(
      block.number,
      "HON::_writeCheckpoint: block number exceeds 32 bits"
    );

    if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
      checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
    } else {
      checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
      numCheckpoints[delegatee] = nCheckpoints + 1;
    }

    emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
  }

  function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
    require(n < 2**32, errorMessage);
    return uint32(n);
  }

  function getChainId() internal view returns (uint256) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return chainId;
  }

  // Fallback function
  fallback() external payable {}

  // This function is called for plain Avax transfers, i.e.
  // for every call with empty calldata.
  receive() external payable {}
}
