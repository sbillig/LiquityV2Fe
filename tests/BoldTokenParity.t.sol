// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {BoldToken} from "../reference/bold/contracts/src/BoldToken.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface SignatureVm {
    function addr(uint256) external returns(address);
    function sign(uint256,bytes32) external returns(uint8,bytes32,bytes32);
    function chainId(uint256) external;
    function warp(uint256) external;
}
contract BoldTokenParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SignatureVm constant sig=SignatureVm(address(vm));
    address constant BO=address(0xb0);address constant AP=address(0xa9);address constant TM=address(0x70);
    address constant SP=address(0x59);address constant CR=address(0xc2);
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant SPENDER=address(0x5);
    BoldToken a;BoldToken b;
    function setUp() public {
        sig.warp(1000);
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/BoldToken.bin")),abi.encode(address(this)));
        vm.recordLogs();address deployed;assembly{deployed:=create(0,add(code,32),mload(code))}
        require(deployed.code.length>0,"Fe deploy");a=BoldToken(deployed);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();vm.recordLogs();b=new BoldToken(address(this));logsEqual(logs,vm.getRecordedLogs());
        require(compare(address(this),abi.encodeCall(a.setBranchAddresses,(TM,SP,BO,AP))));
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal pure {
        require(x.length==y.length,"logs");
        for(uint i;i<x.length;i++) {
            require(keccak256(abi.encode(x[i].topics))==keccak256(abi.encode(y[i].topics)),"topics");
            require(keccak256(x[i].data)==keccak256(y[i].data),"data");
        }
    }
    function compare(address caller,bytes memory data) internal returns(bool) {return comparePair(caller,data,data);}
    function comparePair(address caller,bytes memory dataA,bytes memory dataB) internal returns(bool) {
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory rx)=address(a).call(dataA);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory ry)=address(b).call(dataB);
        logsEqual(logs,vm.getRecordedLogs());require(x==y,"success");require(keccak256(rx)==keccak256(ry),"result");
        require(a.totalSupply()==b.totalSupply(),"supply");require(a.owner()==b.owner(),"owner");
        require(a.collateralRegistryAddress()==b.collateralRegistryAddress(),"registry");
        address[9] memory accounts=[ALICE,BOB,SPENDER,BO,AP,TM,SP,CR,address(0)];
        for(uint i;i<accounts.length;i++) {
            require(a.balanceOf(accounts[i])==b.balanceOf(accounts[i]),"balance");
            require(a.nonces(accounts[i])==b.nonces(accounts[i]),"nonces");
            require(a.allowance(accounts[i],SPENDER)==b.allowance(accounts[i],SPENDER),"allowance");
        }
        return x;
    }
    function testMetadata() public {
        compare(ALICE,abi.encodeCall(a.name,()));compare(ALICE,abi.encodeCall(a.symbol,()));
        compare(ALICE,abi.encodeCall(a.decimals,()));compare(address(this),abi.encodeCall(a.isOwner,()));
        checkDomain(a);checkDomain(b);
        sig.chainId(block.chainid+1);checkDomain(a);checkDomain(b);
    }
    function checkDomain(BoldToken token) internal view {
        bytes32 expected=keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),keccak256("BOLD Stablecoin"),keccak256("1"),block.chainid,address(token)));
        require(token.DOMAIN_SEPARATOR()==expected,"domain hash");
        (bytes1 fields,string memory name,string memory version,uint256 chain,address verifying,bytes32 salt,uint256[] memory extensions)=token.eip712Domain();
        require(fields==hex"0f"&&keccak256(bytes(name))==keccak256("BOLD Stablecoin")&&keccak256(bytes(version))==keccak256("1"));
        require(chain==block.chainid&&verifying==address(token)&&salt==0&&extensions.length==0,"domain fields");
    }
    function testFuzzTokenFlow(uint256 minted,uint256 amount,uint256 approval) public {
        require(compare(BO,abi.encodeCall(a.mint,(ALICE,minted))));
        require(compare(ALICE,abi.encodeCall(a.approve,(SPENDER,approval))));
        compare(SPENDER,abi.encodeCall(a.transferFrom,(ALICE,BOB,amount)));
        compare(ALICE,abi.encodeCall(a.transfer,(ALICE,amount)));
        compare(ALICE,abi.encodeCall(a.increaseAllowance,(SPENDER,amount)));
        compare(ALICE,abi.encodeCall(a.decreaseAllowance,(SPENDER,approval)));
        compare(TM,abi.encodeCall(a.burn,(BOB,amount)));
        compare(AP,abi.encodeCall(a.mint,(BOB,amount)));
    }
    function testFuzzPoolFlow(uint128 amount) public {
        require(compare(BO,abi.encodeCall(a.mint,(ALICE,amount))));
        require(compare(SP,abi.encodeCall(a.sendToPool,(ALICE,SP,amount))));
        require(compare(SP,abi.encodeCall(a.returnFromPool,(SP,BOB,amount))));
        require(compare(SP,abi.encodeCall(a.burn,(BOB,amount))));require(a.totalSupply()==0);
    }
    function testRecipientAndZeroChecks() public {
        require(compare(BO,abi.encodeCall(a.mint,(ALICE,uint256(100)))));
        compare(ALICE,abi.encodeCall(a.transfer,(address(0),uint256(0))));
        comparePair(ALICE,abi.encodeCall(a.transfer,(address(a),uint256(0))),abi.encodeCall(b.transfer,(address(b),uint256(0))));
        comparePair(SPENDER,abi.encodeCall(a.transferFrom,(ALICE,address(a),uint256(0))),abi.encodeCall(b.transferFrom,(ALICE,address(b),uint256(0))));
        require(compare(ALICE,abi.encodeCall(a.transfer,(BO,uint256(1))))); // core addresses are valid recipients
        compare(address(0),abi.encodeCall(a.transfer,(BOB,uint256(0))));
        compare(address(0),abi.encodeCall(a.approve,(SPENDER,uint256(0))));
        compare(ALICE,abi.encodeCall(a.approve,(address(0),uint256(0))));
        compare(BO,abi.encodeCall(a.mint,(address(0),uint256(0))));
        compare(TM,abi.encodeCall(a.burn,(address(0),uint256(0))));
    }
    function testInfiniteAllowanceAndSelfTransfer() public {
        require(compare(BO,abi.encodeCall(a.mint,(ALICE,uint256(123)))));
        require(compare(ALICE,abi.encodeCall(a.approve,(SPENDER,type(uint256).max))));
        require(compare(SPENDER,abi.encodeCall(a.transferFrom,(ALICE,ALICE,uint256(123)))));
        require(a.balanceOf(ALICE)==123&&a.allowance(ALICE,SPENDER)==type(uint256).max);
    }
    function testAuthorizationAndRenunciation() public {
        require(compare(address(this),abi.encodeCall(a.setCollateralRegistry,(CR))));
        require(a.owner()==address(0));
        address[7] memory roles=[BO,AP,TM,SP,CR,ALICE,address(this)];
        for(uint i;i<roles.length;i++) {
            compare(roles[i],abi.encodeCall(a.setBranchAddresses,(TM,SP,BO,AP)));
            compare(roles[i],abi.encodeCall(a.setCollateralRegistry,(CR)));
            compare(roles[i],abi.encodeCall(a.mint,(ALICE,uint256(0))));
            compare(roles[i],abi.encodeCall(a.burn,(ALICE,uint256(0))));
            compare(roles[i],abi.encodeCall(a.sendToPool,(ALICE,SP,uint256(0))));
            compare(roles[i],abi.encodeCall(a.returnFromPool,(SP,ALICE,uint256(0))));
        }
    }
    function permitData(BoldToken token,uint256 key,address spender,uint256 value,uint256 deadline) internal returns(bytes memory) {
        address owner=sig.addr(key);
        bytes32 h=keccak256(abi.encode(keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),owner,spender,value,token.nonces(owner),deadline));
        (uint8 v,bytes32 r,bytes32 s)=sig.sign(key,keccak256(abi.encodePacked(hex"1901",token.DOMAIN_SEPARATOR(),h)));
        return abi.encodeCall(token.permit,(owner,spender,value,deadline,v,r,s));
    }
    function testFuzzPermit(uint128 keySeed,uint256 value) public {
        uint256 key=uint256(keySeed)+1;address owner=sig.addr(key);
        bytes memory da=permitData(a,key,SPENDER,value,1000);bytes memory db=permitData(b,key,SPENDER,value,1000);
        require(comparePair(BOB,da,db));require(a.nonces(owner)==1&&b.nonces(owner)==1);
        require(a.allowance(owner,SPENDER)==value&&b.allowance(owner,SPENDER)==value);
        require(!comparePair(BOB,da,db));require(a.nonces(owner)==1);
        da=permitData(a,key,address(0),value,1000);db=permitData(b,key,address(0),value,1000);
        require(!comparePair(BOB,da,db));require(a.nonces(owner)==1);
    }
    function testPermitDomainAndDeadline() public {
        bytes memory da=permitData(a,123,SPENDER,5,1000);bytes memory db=permitData(b,123,SPENDER,5,1000);
        require(!comparePair(BOB,db,da)); // wrong verifying contract
        sig.chainId(block.chainid+1);require(!comparePair(BOB,da,db));
        da=permitData(a,123,SPENDER,5,1000);db=permitData(b,123,SPENDER,5,1000);
        sig.warp(1001);require(!comparePair(BOB,da,db));require(a.nonces(sig.addr(123))==0);
    }
    function testFuzzInvalidSignatures(uint8 v,bytes32 r,bytes32 s) public {
        compare(BOB,abi.encodeCall(a.permit,(ALICE,SPENDER,uint256(3),uint256(1000),v,r,s)));
        require(a.nonces(ALICE)==0);
    }
}
