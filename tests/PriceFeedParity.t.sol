// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {WETHPriceFeed} from "../reference/bold/contracts/src/PriceFeeds/WETHPriceFeed.sol";
import {RETHPriceFeed} from "../reference/bold/contracts/src/PriceFeeds/RETHPriceFeed.sol";
import {WSTETHPriceFeed} from "../reference/bold/contracts/src/PriceFeeds/WSTETHPriceFeed.sol";
interface FeedVm {
    struct Log {bytes32[] topics;bytes data;address emitter;}
    function readFile(string calldata) external view returns(string memory);
    function parseBytes(string calldata) external pure returns(bytes memory);
    function warp(uint) external;
    function load(address,bytes32) external view returns(bytes32);
    function recordLogs() external;
    function getRecordedLogs() external returns(Log[] memory);
}
contract FeedOracle {
    uint8 public decimals;
    int public answer;
    uint public timestamp=1000;
    uint public mode;
    constructor(uint8 d,int a){decimals=d;answer=a;}
    function setDecimals(uint8 d) external {decimals=d;}
    function set(int a,uint t,uint m) external {answer=a;timestamp=t;mode=m;}
    function latestRoundData() external view returns(uint80,int,uint,uint,uint80){
        uint m=mode;int a=answer;uint t=timestamp;
        if(m==1)revert("oracle failed");
        if(m==2){assembly{revert(0,0)}}
        if(m==5){assembly{for {} 1 {} {}}}
        assembly{
            mstore(0,1) mstore(32,a) mstore(64,t) mstore(96,t) mstore(128,1)
            if eq(m,3) {return(0,159)}
            if eq(m,4) {mstore(0,shl(80,1))}
            if eq(m,6) {mstore(128,shl(80,1))}
            return(0,160)
        }
    }
}
contract FeedRate {
    uint public value=11e17;
    uint public mode;
    function set(uint v,uint m) external {value=v;mode=m;}
    function getExchangeRate() external view returns(uint){return read();}
    function stEthPerToken() external view returns(uint){return read();}
    function read() internal view returns(uint){
        if(mode==1)revert("rate failed");
        if(mode==2){assembly{return(0,0)}}
        if(mode==3){assembly{for {} 1 {} {}}}
        return value;
    }
}
contract FeedBorrower {
    event Called();
    mapping(address=>uint) public calls;
    bool public fail;
    function setFail(bool value) external {fail=value;}
    function shutdownFromOracleFailure() external {require(!fail,"shutdown failed");calls[msg.sender]++;emit Called();}
}
contract PriceFeedParityTest {
    FeedVm constant vm=FeedVm(address(uint160(uint(keccak256("hevm cheat code")))));
    FeedOracle eth;FeedOracle lst;FeedRate rate;FeedBorrower bo;
    address a;address b;uint kind;
    function setUp() public {vm.warp(1000);eth=new FeedOracle(8,2000e8);rate=new FeedRate();bo=new FeedBorrower();}
    function make(uint k) internal {
        kind=k;string memory name=k==0?"WETHPriceFeed":k==1?"RETHPriceFeed":"WSTETHPriceFeed";
        lst=new FeedOracle(k==1?18:8,k==1?int(11e17):int(2000e8));
        bytes memory args=k==0?abi.encode(eth,3600,bo):abi.encode(eth,lst,rate,3600,3600,bo);
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat("build/",name,".bin"))),args);
        vm.recordLogs();address created;assembly{created:=create(0,add(code,32),mload(code))}a=created;require(a.code.length>0&&a.code.length<=24576,"Fe deployment");FeedVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();if(k==0)b=address(new WETHPriceFeed(address(eth),3600,address(bo)));else if(k==1)b=address(new RETHPriceFeed(address(eth),address(lst),address(rate),3600,3600,address(bo)));else b=address(new WSTETHPriceFeed(address(eth),address(lst),address(rate),3600,3600,address(bo)));
        equalLogs(logs,vm.getRecordedLogs());state();
    }
    function equalLogs(FeedVm.Log[] memory x,FeedVm.Log[] memory y) internal view {
        require(x.length==y.length,"event count");for(uint i;i<x.length;i++){
            require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data)),"event data");
            require(x[i].emitter==y[i].emitter||(x[i].emitter==a&&y[i].emitter==b),"emitter");
        }
    }
    function state() internal view {for(uint i;i<(kind==0?6:10);i++)require(vm.load(a,bytes32(i))==vm.load(b,bytes32(i)),"storage");require(bo.calls(a)==bo.calls(b),"shutdown count");}
    function compare(bytes memory data,uint gasLimit) internal returns(bool){
        vm.recordLogs();(bool x,bytes memory p)=a.call{gas:gasLimit}(data);FeedVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();(bool y,bytes memory q)=b.call{gas:gasLimit}(data);equalLogs(logs,vm.getRecordedLogs());
        require(x==y,"success");require(keccak256(p)==keccak256(q),"return/revert");state();return x;
    }
    function fetch(bool redemption) internal returns(bool){return compare(abi.encodeWithSignature(redemption?"fetchRedemptionPrice()":"fetchPrice()"),1000000);}
    function testWethPricesStalenessAndFreeze() public {
        make(0);require(fetch(false));eth.set(2100e8,1000,0);require(fetch(true));
        vm.warp(4600);require(fetch(false));require(uint(WETHPriceFeed(a).priceSource())==2);
        eth.set(3000e8,4600,0);require(fetch(false));require(WETHPriceFeed(a).lastGoodPrice()==2100e18);
    }
    function testRethFallbackMonotonicAndSecondFailure() public {
        make(1);lst.set(11e17,1000,1);require(fetch(false));
        eth.set(1900e8,1000,0);require(fetch(false));eth.set(2500e8,1000,0);require(fetch(true));
        require(RETHPriceFeed(a).lastGoodPrice()==2090e18);
        rate.set(0,0);require(fetch(false));require(uint(RETHPriceFeed(a).priceSource())==2);
        require(bo.calls(a)==1);
    }
    function testWstethFallbackAndEthFailure() public {
        make(2);lst.set(0,1000,0);require(fetch(true));eth.set(1900e8,1000,0);require(fetch(false));
        eth.set(1900e8,1000,1);require(fetch(false));require(uint(WSTETHPriceFeed(a).priceSource())==2);require(bo.calls(a)==1);
    }
    function testMalformedRoundDataIsNotCaught() public {
        make(0);for(uint m=3;m<=6;m++){if(m==5)continue;eth.set(2000e8,1000,m);require(!fetch(false));}
        require(bo.calls(a)==0);eth.set(2000e8,1001,0);require(!fetch(false));
    }
    function testOutOfGasDoesNotShutdown() public {
        make(1);eth.set(2000e8,1000,5);require(!compare(abi.encodeWithSignature("fetchPrice()"),100000));require(bo.calls(a)==0);
    }
    function testRollbackWhenShutdownFails() public {make(2);bo.setFail(true);rate.set(0,0);require(!fetch(false));}
    function testRedemptionDeviationBoundaries() public {
        make(1);
        uint[6] memory values=[uint(1078e15-1),1078e15,1078e15+1,1122e15-1,1122e15,1122e15+1];
        for(uint i;i<values.length;i++){lst.set(int(values[i]),1000,0);require(fetch(false));require(fetch(true));}
        make(2);uint[6] memory usd=[uint(1980e8-1),1980e8,1980e8+1,2020e8-1,2020e8,2020e8+1];
        for(uint i;i<usd.length;i++){lst.set(int(usd[i]),1000,0);require(fetch(false));require(fetch(true));}
    }
    function testCanonicalMalformedAndGasFailures() public {
        make(2);rate.set(11e17,2);require(!fetch(false));rate.set(11e17,3);
        require(!compare(abi.encodeWithSignature("fetchPrice()"),100000));require(bo.calls(a)==0);
        rate.set(11e17,1);require(fetch(false));require(bo.calls(a)==1);
    }
    function testOraclePriorityAndSignedAnswers() public {
        make(1);eth.set(-1,1000,0);lst.set(0,1000,0);rate.set(0,0);require(fetch(false));
        eth.set(2000e8,1000,0);rate.set(11e17,0);make(2);eth.set(-1,1000,0);rate.set(0,0);require(fetch(false));
    }
    function createRaw(bytes memory init) internal returns(address created,bytes memory reason){
        assembly{
            created:=create(0,add(init,32),mload(init))
            let size:=returndatasize()
            reason:=mload(0x40) mstore(reason,size) returndatacopy(add(reason,32),0,size)
            mstore(0x40,and(add(add(reason,63),size),not(31)))
        }
    }
    function invalidConstructor(uint k) internal {
        string memory name=k==0?"WETHPriceFeed":k==1?"RETHPriceFeed":"WSTETHPriceFeed";
        bytes memory args=k==0?abi.encode(eth,3600,bo):abi.encode(eth,lst,rate,3600,3600,bo);
        bytes memory fe=bytes.concat(vm.parseBytes(vm.readFile(string.concat("build/",name,".bin"))),args);
        bytes memory sol=k==0?type(WETHPriceFeed).creationCode:k==1?type(RETHPriceFeed).creationCode:type(WSTETHPriceFeed).creationCode;
        (address x,bytes memory p)=createRaw(fe);(address y,bytes memory q)=createRaw(bytes.concat(sol,args));
        require(x==address(0)&&y==address(0),"invalid constructor accepted");require(keccak256(p)==keccak256(q),"constructor revert");
    }
    function testConstructorInvalidPrecisionAndOracleFailure() public {
        eth.setDecimals(18);invalidConstructor(0);eth.setDecimals(8);eth.set(0,1000,0);invalidConstructor(0);
        eth.set(2000e8,1000,0);lst=new FeedOracle(19,11e18);invalidConstructor(1);
        lst=new FeedOracle(8,2000e8);rate.set(0,0);invalidConstructor(2);
    }
    function testFuzzRethMarketCanonical(uint96 market,uint96 canonical,bool redemption) public {
        make(1);lst.set(int(uint(market)),1000,0);rate.set(uint(canonical),0);fetch(redemption);
    }
    function testFuzzWstethMarketCanonical(uint96 market,uint96 canonical,bool redemption) public {
        make(2);lst.set(int(uint(market)),1000,0);rate.set(uint(canonical),0);fetch(redemption);
    }
}
