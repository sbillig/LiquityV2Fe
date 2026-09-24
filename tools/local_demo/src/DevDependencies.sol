// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
// Local external dependencies, not substitutes for any Fe protocol contract.
contract DevToken {
 string public name;string public symbol;uint8 public decimals=18;
 function setDecimals(uint8 value) external {decimals=value;}
 address public staking;
 function setStaking(address value) external {require(staking==address(0));staking=value;}
 function sendToLQTYStaking(address from,uint amount) external {require(msg.sender==staking);move(from,staking,amount);}
 uint public totalSupply;mapping(address=>uint) public balanceOf;mapping(address=>mapping(address=>uint)) public allowance;
 event Transfer(address indexed from,address indexed to,uint amount);event Approval(address indexed owner,address indexed spender,uint amount);
 constructor(string memory n,string memory s){name=n;symbol=s;}
 function mint(address to,uint amount) public {balanceOf[to]+=amount;totalSupply+=amount;emit Transfer(address(0),to,amount);}
 function approve(address spender,uint amount) external returns(bool){allowance[msg.sender][spender]=amount;emit Approval(msg.sender,spender,amount);return true;}
 function transfer(address to,uint amount) external returns(bool){move(msg.sender,to,amount);return true;}
 function transferFrom(address from,address to,uint amount) external returns(bool){uint allowed=allowance[from][msg.sender];if(allowed!=type(uint).max)allowance[from][msg.sender]-=amount;move(from,to,amount);return true;}
 function move(address from,address to,uint amount) internal {balanceOf[from]-=amount;balanceOf[to]+=amount;emit Transfer(from,to,amount);}
 function deposit() public payable {mint(msg.sender,msg.value);}
 function withdraw(uint amount) external {balanceOf[msg.sender]-=amount;totalSupply-=amount;(bool ok,)=msg.sender.call{value:amount}("");require(ok);emit Transfer(msg.sender,address(0),amount);}
 receive() external payable {deposit();}
}
contract DevOracle {
 uint8 public immutable decimals;int public answer;uint public updatedAt;
 constructor(uint8 d,int a){decimals=d;set(a);}
 function set(int a) public {answer=a;updatedAt=block.timestamp;}
 function latestRoundData() external view returns(uint80,int,uint,uint,uint80){return(1,answer,updatedAt,updatedAt,1);}
}
contract DevRate {
 function getExchangeRate() external pure returns(uint){return 1e18;}
 function stEthPerToken() external pure returns(uint){return 1e18;}
}
contract DevStaking {
 DevToken public immutable lqty;mapping(address=>uint) public stakes;
 constructor(address token){lqty=DevToken(payable(token));lqty.setStaking(address(this));}
 function stake(uint amount) external {lqty.sendToLQTYStaking(msg.sender,amount);stakes[msg.sender]+=amount;}
 function unstake(uint amount) external {stakes[msg.sender]-=amount;lqty.transfer(msg.sender,amount);}
 function getPendingETHGain(address) external pure returns(uint){return 0;}
 function getPendingLUSDGain(address) external pure returns(uint){return 0;}
}
contract DevCreate2 {
 function deploy(bytes32 salt,bytes memory init) external returns(address target) {
  require(init.length<=49152,"initcode limit");assembly{target:=create2(0,add(init,32),mload(init),salt)}
  require(target!=address(0)&&target.code.length>0&&target.code.length<=24576,"deployment failed");
 }
}
interface DevERC20 {
 function balanceOf(address) external view returns(uint);
 function transfer(address,uint) external returns(bool);
 function transferFrom(address,address,uint) external returns(bool);
}
interface DevLoanRecipient {function receiveFlashLoan(address[] calldata,uint[] calldata,uint[] calldata,bytes calldata) external;}
contract DevBalancerVault {
 function flashLoan(address recipient,address[] calldata tokens,uint[] calldata amounts,bytes calldata data) external {
  uint[] memory beforeBalances=new uint[](tokens.length);uint[] memory fees=new uint[](tokens.length);
  require(tokens.length==amounts.length);
  for(uint i;i<tokens.length;i++){beforeBalances[i]=DevERC20(tokens[i]).balanceOf(address(this));require(DevERC20(tokens[i]).transfer(recipient,amounts[i]));}
  DevLoanRecipient(recipient).receiveFlashLoan(tokens,amounts,fees,data);
  for(uint i;i<tokens.length;i++)require(DevERC20(tokens[i]).balanceOf(address(this))>=beforeBalances[i],"flash loan not repaid");
 }
}
contract DevCurvePool {
 address[2] public coins;uint public immutable ratio;
 constructor(address first,address second,uint rate){coins=[first,second];ratio=rate;}
 function quote(uint i,uint j,uint amount) public view returns(uint){require(i<2&&j<2&&i!=j);return i==0?amount*ratio:amount/ratio;}
 function exchange(uint i,uint j,uint amount,uint minimum) public returns(uint out){out=quote(i,j,amount);require(out>=minimum,"slippage");require(DevERC20(coins[i]).transferFrom(msg.sender,address(this),amount));require(DevERC20(coins[j]).transfer(msg.sender,out));}
 function exchange(int128 i,int128 j,uint amount,uint minimum) external returns(uint){return exchange(uint(uint128(i)),uint(uint128(j)),amount,minimum);}
 function get_dy(int128 i,int128 j,uint amount) external view returns(uint){return quote(uint(uint128(i)),uint(uint128(j)),amount);}
 function get_dx(int128 i,int128 j,uint out) external view returns(uint){require(i>=0&&j>=0&&i!=j);return i==0?(out+ratio-1)/ratio:out*ratio;}
}
contract DevUniRouter {
 mapping(address=>uint) public price;
 struct ExactInputSingleParams {address tokenIn;address tokenOut;uint24 fee;address recipient;uint deadline;uint amountIn;uint amountOutMinimum;uint160 sqrtPriceLimitX96;}
 struct ExactOutputSingleParams {address tokenIn;address tokenOut;uint24 fee;address recipient;uint deadline;uint amountOut;uint amountInMaximum;uint160 sqrtPriceLimitX96;}
 struct ExactInputParams {bytes path;address recipient;uint deadline;uint amountIn;uint amountOutMinimum;}
 function setPrice(address token,uint value) external {price[token]=value;}
 function quote(address from,address to,uint amount) public view returns(uint){require(price[from]>0&&price[to]>0);return amount*price[from]/price[to];}
 function exactInputSingle(ExactInputSingleParams calldata p) external returns(uint out){require(p.deadline>=block.timestamp);out=quote(p.tokenIn,p.tokenOut,p.amountIn);require(out>=p.amountOutMinimum);require(DevERC20(p.tokenIn).transferFrom(msg.sender,address(this),p.amountIn));require(DevERC20(p.tokenOut).transfer(p.recipient,out));}
 function exactOutputSingle(ExactOutputSingleParams calldata p) external returns(uint amount){require(p.deadline>=block.timestamp);amount=(p.amountOut*price[p.tokenOut]+price[p.tokenIn]-1)/price[p.tokenIn];require(amount<=p.amountInMaximum);require(DevERC20(p.tokenIn).transferFrom(msg.sender,address(this),amount));require(DevERC20(p.tokenOut).transfer(p.recipient,p.amountOut));}
 function endpoints(bytes calldata path) public pure returns(address first,address last,uint hops){require(path.length>=43&&(path.length-20)%23==0);assembly{first:=shr(96,calldataload(path.offset)) last:=shr(96,calldataload(add(path.offset,sub(path.length,20))))}hops=(path.length-20)/23;}
 function exactInput(ExactInputParams calldata p) external returns(uint out){require(p.deadline>=block.timestamp);(address first,address last,)=endpoints(p.path);out=quote(first,last,p.amountIn);require(out>=p.amountOutMinimum);require(DevERC20(first).transferFrom(msg.sender,address(this),p.amountIn));require(DevERC20(last).transfer(p.recipient,out));}
 function quoteExactInput(bytes calldata path,uint amount) external view returns(uint,uint160[] memory,uint32[] memory,uint){(address first,address last,uint hops)=endpoints(path);return(quote(first,last,amount),new uint160[](hops),new uint32[](hops),0);}
 function quoteExactOutput(bytes calldata path,uint amount) external view returns(uint,uint160[] memory,uint32[] memory,uint){(address last,address first,uint hops)=endpoints(path);return((amount*price[last]+price[first]-1)/price[first],new uint160[](hops),new uint32[](hops),0);}
}
contract DevGauge {
 uint public deposited;uint public duration;
 function deposit_reward_token(address token,uint amount,uint seconds_) external {require(DevERC20(token).transferFrom(msg.sender,address(this),amount));deposited+=amount;duration=seconds_;}
}
contract DevDistributionCreator {
 struct Campaign {bytes32 id;address owner;address rewardToken;uint amount;uint32 campaignType;uint32 startTimestamp;uint32 duration;bytes data;}
 mapping(address=>bool) public accepted;uint public calls;uint public amount;uint public timestamp;uint public duration;bytes32 public dataHash;
 function acceptConditions() external {accepted[msg.sender]=true;}
 function createCampaign(Campaign calldata p) external returns(bytes32) {require(accepted[msg.sender]&&p.campaignType==13);require(DevERC20(p.rewardToken).transferFrom(msg.sender,address(this),p.amount));calls++;amount=p.amount;timestamp=p.startTimestamp;duration=p.duration;dataHash=keccak256(p.data);return keccak256(abi.encode(msg.sender,calls,p));}
}
