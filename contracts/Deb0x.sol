// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./Deb0xERC20.sol";
import "./Deb0xGovernor.sol";

contract Deb0x is Ownable {
    //Message setup
    Deb0xERC20 public deboxERC20;
    Deb0xGovernor public governor;
    uint16 public fee = 1000;

    mapping(address => string) private encryptionKeys;

    mapping(address => mapping(address => string[])) private messages;

    mapping(address => address[]) private messageSenders;

    //Tokenomic setup
    uint256 public rewardRate = 100;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public balanceERC20;

    mapping(address => uint256) public userRewardPerTokenPaid;

    mapping(address => uint256) public rewards;

    uint256 public totalSupply;

    uint8 year = 1;
    uint256 initialTimestamp;
    uint256 msgReward = 225 * (10**16);

    constructor() {
        deboxERC20 = new Deb0xERC20(address(this));
        deboxERC20.approve(address(this), deboxERC20.totalSupply());
        balanceERC20[address(this)] = deboxERC20.totalSupply();
        initialTimestamp = block.timestamp;
    }

    function setFee(uint16 newFee) public onlyOwner {
        fee = newFee;
    }

    function setRewardRate(uint256 newRewardRate) public onlyOwner {
        rewardRate = newRewardRate;
    }

    //Message Functions
    function setKey(string memory encryptionKey) public {
        encryptionKeys[msg.sender] = encryptionKey;
    }

    function send(address to, string memory payload)
        public
        payable
        updateReward(msg.sender)
    {
        uint256 startGas = gasleft();
                                     
        if (block.timestamp > year * 2050000 + initialTimestamp) {
            year += 1;
            msgReward = msgReward / 2;
        }

        if (messages[to][msg.sender].length == 0) {
            messageSenders[to].push(msg.sender);
        }

        balanceERC20[address(this)] -= msgReward;
        balanceERC20[msg.sender] += msgReward;
        totalSupply += msgReward;

        messages[to][msg.sender].push(payload);

        uint256 gasUsed = startGas - gasleft();
        require(
            msg.value >=
                ((gasUsed+ 21000 + 50000) * tx.gasprice  * fee) / 10000,
            "Deb0x: must pay 10% of transaction cost"
        );
    }

    function fetchMessages(address to, address from)
        public
        view
        returns (string[] memory)
    {
        return messages[to][from];
    }

    function fetchMessageSenders(address to)
        public
        view
        returns (address[] memory)
    {
        return messageSenders[to];
    }

    function getKey(address account) public view returns (string memory) {
        return encryptionKeys[account];
    }

    //Tokenomic functions
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        rewards[account] = earnedNative(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    function stakeERC20(uint256 _amount)
        external
        payable
        updateReward(msg.sender)
    {
        require(_amount != 0, "Deb0x: your amount is 0");

        totalSupply += _amount;
        balanceERC20[msg.sender] += _amount;

        deboxERC20.transferFrom(msg.sender, address(this), _amount);
    }

    function unStakeERC20(uint256 _amount) external updateReward(msg.sender) {
        require(_amount != 0, "Deb0x: your amount is 0");
        require(
            balanceERC20[msg.sender] - _amount >= 0,
            "Deb0x: insufficient balance"
        );

        totalSupply -= _amount;
        balanceERC20[msg.sender] -= _amount;
        deboxERC20.transferFrom(address(this), msg.sender, _amount);
    }

    function getRewardNative() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "Deb0x: your reward balance is 0");

        rewards[msg.sender] = 0;

        sendViaCall(payable(msg.sender), reward);
    }

    function sendViaCall(address payable _to, uint256 _amount) private {
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "Deb0x: failed to send amount");
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) /
                totalSupply);
    }

    function earnedNative(address account) public view returns (uint256) {
        return
            ((balanceERC20[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    function contractBalance() public view returns (uint256) {
        return address(this).balance;
    }
}