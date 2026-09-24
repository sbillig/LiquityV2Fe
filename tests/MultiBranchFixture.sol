// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import "./BorrowerOperationsSystem.t.sol";
abstract contract MultiBranchFixture {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant ROUTER=address(0x100);
    struct System {
        CollateralRegistry cr;AddressesRegistry registry;ActivePool active;DefaultPool defaults;StabilityPool sp;BoldToken bold;BorrowerSystemCollateral coll;BorrowerSystemCollateral weth;
        WETHPriceFeed oracleFeed;FeedOracle oracle;BorrowerOperations bo;TroveManager manager;TroveNFT nft;SortedTroves sorted;CollSurplusPool surplus;address gasPool;BorrowerSystemPrice feed;
    }
    function code(string memory name,bool fe) internal returns(bytes memory){
        if(fe&&(keccak256(bytes(name))==keccak256("BorrowerOperations")||keccak256(bytes(name))==keccak256("BorrowerOpening")||keccak256(bytes(name))==keccak256("BorrowerAdjustments")||keccak256(bytes(name))==keccak256("BorrowerBatches")))return vm.parseBytes(vm.readFile(string.concat(BOSystemVm(address(vm)).envOr("LIQUITY_BORROWER_ARTIFACTS","build"),"/",name,".bin")));
        if(fe)return vm.parseBytes(vm.readFile(string.concat(BOSystemVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin")));
        bytes32 k=keccak256(bytes(name));
        if(k==keccak256("GasCompZapper"))return type(GasCompZapper).creationCode;
        if(k==keccak256("WETHZapper"))return type(WETHZapper).creationCode;
        if(k==keccak256("RedemptionHelper"))return type(RedemptionHelper).creationCode;
        if(k==keccak256("CollateralRegistry"))return type(CollateralRegistry).creationCode;
        if(k==keccak256("DebtInFrontHelper"))return type(DebtInFrontHelper).creationCode;
        if(k==keccak256("HintHelpers"))return type(HintHelpers).creationCode;
        if(k==keccak256("MultiTroveGetter"))return type(MultiTroveGetter).creationCode;
        if(k==keccak256("WETHPriceFeed"))return type(WETHPriceFeed).creationCode;
        if(k==keccak256("BorrowerOperations"))return type(BorrowerOperations).creationCode;
        if(k==keccak256("AddressesRegistry"))return type(AddressesRegistry).creationCode;
        if(k==keccak256("ActivePool"))return type(ActivePool).creationCode;
        if(k==keccak256("DefaultPool"))return type(DefaultPool).creationCode;
        if(k==keccak256("StabilityPool"))return type(StabilityPool).creationCode;
        if(k==keccak256("BoldToken"))return type(BoldToken).creationCode;
        if(k==keccak256("TroveManager"))return type(TroveManager).creationCode;
        if(k==keccak256("TroveNFT"))return type(TroveNFT).creationCode;
        if(k==keccak256("SortedTroves"))return type(SortedTroves).creationCode;
        if(k==keccak256("CollSurplusPool"))return type(CollSurplusPool).creationCode;
        if(k==keccak256("GasPool"))return type(GasPool).creationCode;
        revert("unknown contract");
    }
    function predict(bytes memory init) internal view virtual returns(address){return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff",address(this),bytes32(0),keccak256(init))))));}
    function deploy(bytes memory init) internal virtual returns(address target){require(init.length<=49152,"initcode");assembly{target:=create2(0,add(init,32),mload(init),0)}require(target.code.length>0&&target.code.length<=24576,"deploy");}
    function id(address owner,uint index) internal pure returns(uint){return uint(keccak256(abi.encode(owner,owner,index)));}
    function open(System memory s,uint index,address owner,uint coll,uint rate) internal {
        s.coll.mint(owner,coll+375e14);
        if(address(s.weth)!=address(s.coll)){s.weth.mint(owner,375e14);vm.prank(owner);s.weth.approve(address(s.bo),type(uint).max);}
        vm.prank(owner);s.coll.approve(address(s.bo),type(uint).max);
        vm.prank(owner);uint opened=s.bo.openTrove(owner,index,coll,3000e18,0,0,rate,type(uint).max,address(0),address(0),address(0));
        require(opened==id(owner,index),"trove ID");
    }
    function conserve(System memory s) internal view {
        require(s.bold.balanceOf(address(s.sp))==s.sp.getTotalBoldDeposits()+s.sp.getYieldGainsOwed()+s.sp.getYieldGainsPending(),"BOLD conservation");
        require(s.coll.balanceOf(address(s.active))==s.active.getCollBalance(),"active collateral");
        require(s.coll.balanceOf(address(s.defaults))==s.defaults.getCollBalance(),"default collateral");
        require(s.coll.balanceOf(address(s.sp))==s.sp.getCollBalance(),"SP collateral");
    }
}
