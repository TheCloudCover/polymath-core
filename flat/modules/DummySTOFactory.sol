pragma solidity ^0.4.21;

contract IST20 {

    // off-chain hash
    bytes32 public tokenDetails;

    //transfer, transferFrom must respect use respect the result of verifyTransfer
    function verifyTransfer(address _from, address _to, uint256 _amount) public view returns (bool success);

    //used to create tokens
    function mint(address _investor, uint256 _amount) public returns (bool success);
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;


  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}

contract ISecurityToken is IST20, Ownable {

    //TODO: Factor out more stuff here
    function checkPermission(address _delegate, address _module, bytes32 _perm) public view returns(bool);

}

/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
  function totalSupply() public view returns (uint256);
  function balanceOf(address who) public view returns (uint256);
  function transfer(address to, uint256 value) public returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
  function allowance(address owner, address spender) public view returns (uint256);
  function transferFrom(address from, address to, uint256 value) public returns (bool);
  function approve(address spender, uint256 value) public returns (bool);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

//Simple interface that any module contracts should implement
contract IModuleFactory is Ownable {

    ERC20 public polyToken;

    //Should create an instance of the Module, or throw
    function deploy(bytes _data) external returns(address);

    function getType() public view returns(uint8);

    function getName() public view returns(bytes32);

    //Return the cost (in POLY) to use this factory
    function getCost() public view returns(uint256);

    function getDescription() public view returns(string);

    function getTitle() public view returns(string);

    function getInstructions() public view returns (string);

    //Pull function sig from _data
    function getSig(bytes _data) internal pure returns (bytes4 sig) {
        uint len = _data.length < 4 ? _data.length : 4;
        for (uint i = 0; i < len; i++) {
            sig = bytes4(uint(sig) + uint(_data[i]) * (2 ** (8 * (len - 1 - i))));
        }
    }

}

//Simple interface that any module contracts should implement
contract IModule {

    address public factory;

    address public securityToken;

    function IModule(address _securityToken) public {
        securityToken = _securityToken;
        factory = msg.sender;
    }

    function getInitFunction() public returns (bytes4);
    
    //Allows owner, factory or permissioned delegate
    modifier withPerm(bytes32 _perm) {
        bool isOwner = msg.sender == ISecurityToken(securityToken).owner();
        bool isFactory = msg.sender == factory;
        require(isOwner||isFactory||ISecurityToken(securityToken).checkPermission(msg.sender, address(this), _perm));
        _;
    }

    modifier onlyOwner {
        require(msg.sender == ISecurityToken(securityToken).owner());
        _;
    }

    modifier onlyFactory {
        require(msg.sender == factory);
        _;
    }

    modifier onlyFactoryOwner {
        require(msg.sender == IModuleFactory(factory).owner());
        _;
    }

    function getPermissions() public view returns(bytes32[]);
}

contract ISTO is IModule {

    enum FundraiseType { ETH, POLY }
    FundraiseType public fundraiseType;

    address public polyAddress;

    function verifyInvestment(address _beneficiary, uint256 _fundsAmount) public view returns(bool) {
        return ERC20(polyAddress).allowance(_beneficiary, address(this)) >= _fundsAmount;
    }

    function getRaisedEther() public view returns (uint256);

    function getRaisedPOLY() public view returns (uint256);

    function getNumberInvestors() public view returns (uint256);

    function _check(uint8 _fundraiseType, address _polyToken) internal {
        require(_fundraiseType == 0 || _fundraiseType == 1);
        if (_fundraiseType == 0) {
            fundraiseType = FundraiseType.ETH;
        }
        if (_fundraiseType == 1) {
            require(_polyToken != address(0));
            fundraiseType = FundraiseType.POLY;
            polyAddress = _polyToken;
        }
    }

    function _forwardPoly(address _beneficiary, address _to, uint256 _fundsAmount) internal {
        ERC20(polyAddress).transferFrom(_beneficiary, _to, _fundsAmount);
    }

}

contract DummySTO is ISTO {

    bytes32 public constant ADMIN = "ADMIN";

    uint256 public investorCount;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public cap;
    string public someString;

    event LogGenerateTokens(address _investor, uint256 _amount);

    mapping (address => uint256) public investors;

    function DummySTO(address _securityToken) public
    IModule(_securityToken)
    {
    }

    function configure(uint256 _startTime, uint256 _endTime, uint256 _cap, string _someString) public onlyFactory {
        startTime = _startTime;
        endTime = _endTime;
        cap = _cap;
        someString = _someString;
    }

    function getInitFunction() public returns (bytes4) {
        return bytes4(keccak256("configure(uint256,uint256,uint256,string)"));
    }

    function generateTokens(address _investor, uint256 _amount) public onlyOwner {
        require(_amount > 0);
        IST20(securityToken).mint(_investor, _amount);
        if (investors[_investor] == 0) {
            investorCount = investorCount + 1;
        }
        //TODO: Add SafeMath maybe
        investors[_investor] = investors[_investor] + _amount;
        emit LogGenerateTokens (_investor, _amount);
    }

    function getRaisedEther() public view returns (uint256) {
        return 0;
    }

    function getRaisedPOLY() public view returns (uint256) {
        return 0;
    }

    function getNumberInvestors() public view returns (uint256) {
        return investorCount;
    }

    function getPermissions() public view returns(bytes32[]) {
        bytes32[] memory allPermissions = new bytes32[](1);
        allPermissions[0] = ADMIN;
        return allPermissions;
    }

}

contract DummySTOFactory is IModuleFactory {

    function deploy(bytes _data) external returns(address) {
        //polyToken.transferFrom(msg.sender, owner, getCost());
        //Check valid bytes - can only call module init function
        DummySTO dummySTO = new DummySTO(msg.sender);
        //Checks that _data is valid (not calling anything it shouldn't)
        require(getSig(_data) == dummySTO.getInitFunction());
        require(address(dummySTO).call(_data));
        return address(dummySTO);
    }

    function getCost() public view returns(uint256) {
        return 0;
    }

    function getType() public view returns(uint8) {
        return 3;
    }

    function getName() public view returns(bytes32) {
        return "DummySTO";
    }

    function getDescription() public view returns(string) {
        return "Dummy STO";
    }

    function getTitle() public view returns(string) {
        return "Dummy STO";
    }

    function getInstructions() public view returns(string) {
        return "Dummy STO - you can mint tokens at will";
    }

}