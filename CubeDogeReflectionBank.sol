/*

CubeDoge - Reflection Bank

*/

pragma solidity =0.8.15;
// SPDX-License-Identifier: MIT

interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Router {
    function WETH() external pure returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

abstract contract Authorized{
    address private _owner;
    mapping (address => bool) _authorized;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = msg.sender;
        _owner = msgSender;
        _authorized[_owner] = true;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }
    
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    
    modifier onlyAuthorized {
        require(_authorized[msg.sender], "Authorization: caller is not the authorized");
        _;
    }
    
    function manageAuthorization(address account, bool authorize) public onlyOwner {
        _authorized[account] = authorize;
    }
    
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
    
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    
}

contract ReflectionBank is Authorized {

    uint256 public depositedTokenBalance;
    IERC20 public immutable token;
    IUniswapV2Router public router;

    bool public reflectionBankActive;
    bool public initiatedEmergencyWithdrawal;
    uint256 public timeInitiatedEmergencyWithdrawal;
    uint256 public timeLastEmergencyWithdrawal;
    uint256 public emergencyWithdrawalCount;

    event FundsClaimed(uint256 indexed fundsToClaim);
    event TokensDeposited(uint256 indexed depositedTokenAmount);
    event ReflectionsSwapped(uint256 indexed amountSwapped);
    event RouterChanged(address indexed newRouter);
    event EmergencyWithdrawInitiated(
        uint256 indexed amountToBeWithdrawn, 
        uint256 indexed secondsRemaining);
    event EmergencyWithdrawal(uint256 indexed amountWithdrawn);

    constructor(address tokenAddress, address routerAddress){
        token = IERC20(tokenAddress);
        router = IUniswapV2Router(routerAddress);
    }
    
    receive () payable external{}

    function reflectionBalance() view public returns (uint256) {
        return token.balanceOf(address(this)) - depositedTokenBalance;
    }

    function depositTokens(uint256 depositedTokenAmount) external onlyAuthorized {      
        require(initiatedEmergencyWithdrawal != true, 
            "ReflectionBank: emergency-withdrawal in progress");
        require(depositedTokenBalance <= token.balanceOf(msg.sender), 
            "ReflectionBank: depositor token balance insufficient");
        require(depositedTokenAmount > 0, 
            "ReflectionBank: deposit must be positive");
        token.transferFrom(msg.sender, address(this), depositedTokenAmount);
        if(depositedTokenBalance == 0)
            reflectionBankActive = true;
        depositedTokenBalance += depositedTokenAmount;
        
        emit TokensDeposited(depositedTokenAmount);
    }

    function swapReflections(bool usePercentage, uint256 quantifier) external onlyAuthorized {
        require(reflectionBankActive == true, "ReflectionBank: Reflection bank inactive!");                
        if(usePercentage)
            require(quantifier >= 0 && quantifier <= 100, 
                "ReflectionBank: Percentage must be in range [0,100]");
        else{
            require(reflectionBalance() >= quantifier, 
                "ReflectionBank: Insufficient reflection balance");
        }
        uint256 amountToSwap = usePercentage ? (quantifier * reflectionBalance() / 100) : quantifier;            

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();
        token.approve(address(router), amountToSwap);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
        
        emit ReflectionsSwapped(amountToSwap);
    }

    function claimFunds() external onlyAuthorized {
        uint256 fundsToClaim = address(this).balance;
        payable(msg.sender).transfer(fundsToClaim);

        emit FundsClaimed(fundsToClaim);
    }

    function changeRouter(address newRouter) external onlyOwner {
        require(newRouter != address(router), "ReflectionBank: router argument already in use");
        router = IUniswapV2Router(newRouter);

        emit RouterChanged(newRouter);
    }

    function initiateEmergencyWithdraw() external onlyOwner {
        require(reflectionBankActive == true, "ReflectionBank: reflection bank not yet activated");
        reflectionBankActive = false;
        timeInitiatedEmergencyWithdrawal = block.timestamp;
        initiatedEmergencyWithdrawal = true;

        emit EmergencyWithdrawInitiated(depositedTokenBalance / 3, timeInitiatedEmergencyWithdrawal);
    }

    function emergencyWithdraw(address withdrawReceiver) external onlyOwner {
        require(initiatedEmergencyWithdrawal == true, 
            "ReflectionBank: emergency withdrawal no started");
        require(block.timestamp >= timeInitiatedEmergencyWithdrawal + 3 minutes, 
            "ReflectionBank: Time elapsed since emergency-withdrawal init. insufficient");
        require(block.timestamp >= timeLastEmergencyWithdrawal + 3 minutes,
            "ReflectionBank: Time elapsed since last emergency-withdrawal insufficient");
                    
        uint256 amountToWithdraw;
        if(emergencyWithdrawalCount == 0){
            amountToWithdraw = depositedTokenBalance / 3;              
        }
        else if(emergencyWithdrawalCount == 1){
            amountToWithdraw = depositedTokenBalance / 3;            
        }
        else if(emergencyWithdrawalCount == 2){
            amountToWithdraw = token.balanceOf(address(this));            
        }
        else{
            return;
        }
        token.transfer(withdrawReceiver, amountToWithdraw);            
        emergencyWithdrawalCount++;                   
        timeLastEmergencyWithdrawal = block.timestamp;

        emit EmergencyWithdrawal(amountToWithdraw);
    }

}