pragma solidity >=0.4.25;
import "./TestCreditContract.sol";

//Last updated by Zol, 2020.01.14
//Check comments and do refactor

/*
This contract is for USD based Ethereum stablecoins like Tether, USDC, DAI, PAXOS, GEMINI...
Loan amount should be declared in USD cent. Custom functions should handle different decimals of the different stablecoins
*/

contract TestCredit {
    
    event CreditOfferCreated(uint indexed _creditOfferCounter, uint indexed _lendersId, uint _loanAmount, uint _loanType, uint _loanLength, uint _interestRate);
    event CreditClaimCreated(uint indexed _creditClaimCounter, uint indexed _borrowersId, uint _loanAmount, uint _loanType, uint _loanLength, uint _interestRate);
    event NewCredit(address indexed _address);
    
    address public contractOwner;
    address MC2Address = 0x6E063426Cb913de344d10BB4f79d1afF4f078276; 
    address[] public stableCoins = { 0xST2address, 0xST6, 0xST9, 0xST18}; //should change them to test tokens addresses
        
    TestUsersInterface tui = TestUsersInterface(0xafed8B8245BaD4063C0E2aeb459B7Bf78c11a488); 
    
    address[] public serverAddress;
    mapping(address => bool) public isMCServer;
    
    struct CreditOffer {
        address lendersAddress;
        uint lendersId;
        uint loanAmount;
        address coinAddress;
        uint loanType;
        uint loanLength;
        uint periodNumber;
        uint interestRate; //periodical
        uint minCreditScore;
        uint offerLastTo;
    }
    CreditOffer[] public creditOffers;
    uint public creditOfferCounter = 0;
    
    struct CreditClaim {
        address borrowersAddress;
        uint borrowersId;
        uint loanAmount;
        uint loanType;
        uint loanLength;
        uint periodNumber;
        uint interestRate; //periodical
        uint borrowersCreditScore;
        uint claimLastTo;
    } 
    CreditClaim[] public creditClaims;
    uint public creditClaimCounter = 0;
    
    address[] public Credits;
    uint[][] public creditsByExpiration; //public helyett inkább majd getter function kell
    uint public creditCounter = 0;
    
    constructor () public {
        contractOwner = msg.sender;
        setServer(msg.sender);
    }
    
    modifier onlyOwnerOf(uint _userId) {
        require(tui.getUserByAddress(msg.sender) == _userId);
        _;
    }
    
    modifier onlyOwnerOfOffer(uint _offerId) {
        require(msg.sender == creditOffers[_offerId].lendersAddress);
        _;
    }
    
    modifier onlyOwnerOfClaim(uint _claimId) {
        require(msg.sender == creditClaims[_claimId].borrowersAddress);
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == contractOwner);
        _;
    }
    
    modifier onlyServer() {
        require(isMCServer[msg.sender] == true);
        _;
    }
    
    function setServer(address _addr) public onlyOwner {
        require(_addr != address(0));
        serverAddress.push(_addr);
        isMCServer[_addr] = true;
    }
    
    function modifyServer(address _addr, uint _id) public onlyOwner {
        require(_addr != address(0));
        isMCServer[serverAddress[_id]] = false;
        serverAddress[_id] = _addr;
        isMCServer[_addr] = true;
    }
    
    function setStableCoin(address _stableCoinAddress) private {
      
    }
    
    function getBalanceInUSD(address _addr, address _stableCoinAddress) public view returns(uint) {
        StableCoinInterface sci = StableCoinInterface(_stableCoinAddress);
        uint customBalance = sci.balanceOf(_addr);
        uint customDecimals = sci.decimals();
        uint balanceInUSD = uint(customBalance * 100 / 10 ** customDecimals); //USD balance is USD cent
        return(balanceInUSD);
    }
    
    function allowanceInUSD(address _addr, address _stableCoinAddress) public view returns(uint) {
        StableCoinInterface sci = StableCoinInterface(_stableCoinAddress);
        uint customAllowance = sci.allowance(_addr, address(this));
        uint customDecimals = sci.decimals();
        uint allowanceInUSD = uint(customAllowance * 100 / 10 ** customDecimals); //USD allowance is USD cent
        return(allowanceInUSD);
    }
    
    //Check balance in every stablecoins from our stableCoins array
    //Should make it flexible with a tupple and update stableCoins array function
    function checkBalance(address _addr) public view returns(uint, uint, uint, uint) {
        uint ST2Balance = getBalanceInUSD(_addr, stableCoins[0]);
        uint ST6Balance = getBalanceInUSD(_addr, stableCoins[1]);
        uint ST9Balance = getBalanceInUSD(_addr, stableCoins[2]);
        uint ST18Balance = getBalanceInUSD(_addr, stableCoins[3]);
        return(ST2Balance, ST6Balance, ST9Balance, ST18Balance);
    }
    
    //Check allowance in every stablecoins from our stableCoins array
    //Should make it flexible with a tupple and update stableCoins array function
    function checkAllowance(address _addr) public view returns(uint, uint, uint, uint) {
        uint ST2allowance = allowanceInUSD(_addr, stableCoins[0]);
        uint ST6allowance = allowanceInUSD(_addr, stableCoins[1]);
        uint ST9allowance = allowanceInUSD(_addr, stableCoins[2]);
        uint ST18allowance = allowanceInUSD(_addr, stableCoins[3]);
        return(ST2allowance, ST6allowance, ST9allowance, ST18allowance);
    }
            
    function createCreditOffer(uint _loanAmount, uint _loanType, uint _loanLength, uint _periodNumber, uint _interestRate, uint _minCreditScore, uint _lastTo, address _stableCoinAddres) public {
        //require(tui.checkUsersAddress(msg.sender) == true);??
        StableCoinInterface sci = StableCoinInterface(_stableCoinAddress);
        require(getBalanceInUSD(msg.sender, _stableCoinAddress) >= _loanAmount);
        require(allowanceInUSD(msg.sender, _stableCoinAddress) >= _loanAmount);
        uint creditOfferLastTo = now + _lastTo;
        uint lendersId = getSenderId(msg.sender);
        creditOffers.push(CreditOffer(msg.sender, lendersId, _loanAmount, _stableCoinAddress, _loanType, _loanLength, _periodNumber, _interestRate, _minCreditScore, creditOfferLastTo));
        creditOfferCounter ++;
        sci.transferFrom(msg.sender, address(this), _loanAmount);
        emit CreditOfferCreated(creditOfferCounter, lendersId, _loanAmount, _loanType, _loanLength, _interestRate);
    }
    
    function createCreditClaim(uint _loanAmount, uint _loanType, uint _loanLength, uint _periodNumber, uint _interestRate, uint _lastTo) public {
        uint toAllowAmount = calcRedeem(_loanAmount, _periodNumber, _interestRate) * _periodNumber;
        require(tui.checkUsersAddress(msg.sender) == true);
        require(sti.allowance(msg.sender, address(this)) >= toAllowAmount); 
        uint creditClaimersId = getSenderId(msg.sender);
        uint creditScoreOfTheClaimer;
        (creditScoreOfTheClaimer,)= tui.getUserPublicData(creditClaimersId);
        uint creditClaimLastTo = now + _lastTo;
        creditClaims.push(CreditClaim(msg.sender, creditClaimersId, _loanAmount, _loanType, _loanLength, _periodNumber, _interestRate, creditScoreOfTheClaimer, creditClaimLastTo));
        creditClaimCounter ++;
        //end time of CreditClaim?
        emit CreditClaimCreated(creditClaimCounter, creditClaimersId, _loanAmount, _loanType, _loanLength, _interestRate);
    }
    
    /*
    Offerhandling may have its own smart contract
    @@TODO onlyOwnerOfOffer, onlyOwnerOfclaim modifiers
    */
    function changeCreditOfferAmount(uint _offerId, uint _amount) public onlyOwnerOfOffer(_offerId){
       creditOffers[_offerId].loanAmount -= _amount; 
       sti.transfer(msg.sender, _amount);
    }
    
    function changeCreditClaimAmount(uint _claimId, uint _amount) public onlyOwnerOfClaim(_claimId) {
        creditClaims[_claimId].loanAmount -= _amount; 
        sti.transfer(msg.sender, _amount);
    }
    
    function deleteOffer(uint _offerId) public onlyOwnerOfOffer(_offerId){
       creditOffers[_offerId].offerLastTo = 0;
       sti.transfer(msg.sender, creditOffers[_offerId].loanAmount);
       creditOffers[_offerId].loanAmount = 0;
    }
    
    function deleteClaim(uint _claimId) public onlyOwnerOfClaim(_claimId){
       creditClaims[_claimId].claimLastTo = 0;
       sti.transfer(msg.sender, creditClaims[_claimId].loanAmount);
       creditClaims[_claimId].loanAmount = 0;
    }

    function getSenderId(address _addr) public view returns(uint) {
        uint claimerId = tui.getUserByAddress(_addr);
        return(claimerId);
    }
    
    function getSenderCreditScore(address _addr) public view returns(uint) {
        uint claimerIdCreditScore;
        (claimerIdCreditScore,) = tui.getUserPublicData(tui.getUserByAddress(_addr));    
        return(claimerIdCreditScore);
    }
    
    //Minimum credit amount is 1000
    function acceptCreditOffer(uint _offerId, uint _amount) public {
        require(_amount >= 1000);
        uint paybacksInterest = creditOffers[_offerId].interestRate; //interestRate per periods
        uint periods = creditOffers[_offerId].periodNumber;
        uint newReedem = calcRedeem(_amount, periods, paybacksInterest);
        uint payback = newReedem * periods;
        require(sti.allowance(msg.sender, address(this)) >= payback);
        require(creditOffers[_offerId].offerLastTo >= now);
        uint lender = creditOffers[_offerId].lendersId;
        uint claimerId = getSenderId(msg.sender);
        uint claimerIdCreditScore = getSenderCreditScore(msg.sender);        
        require(claimerIdCreditScore >= creditOffers[_offerId].minCreditScore);
        require(creditOffers[_offerId].loanAmount >= _amount);
        uint offeredLoanLength = creditOffers[_offerId].loanLength;
        uint amountToBorrower = _amount * 995 / 1000;
        uint amountToMC2 = _amount * 5 / 1000;
        sti.transfer(msg.sender, amountToBorrower);
        sti.transfer(MC2Address, amountToMC2);
        creditOffers[_offerId].loanAmount -= _amount;
        
        TestCreditContract newCredit = new TestCreditContract(creditCounter, lender, claimerId, _amount, paybacksInterest, periods, newReedem, offeredLoanLength, address(this));
        tui.setCreditContractAddress(address(newCredit), claimerId, creditCounter);
        creditCounter = Credits.push(address(newCredit));
        emit NewCredit(address(newCredit));
    }
    
    //Minimum credit amount is 1000
    function acceptCreditClaim(uint _claimId, uint _amount) public {
        require(_amount >= 1000);
        uint paybacksInterest = creditClaims[_claimId].interestRate;
        uint loanClaimPeriods = creditClaims[_claimId].periodNumber;
        uint loanClaimRedeem = calcRedeem(_amount, loanClaimPeriods, paybacksInterest);
        uint loanClaimMinApproval = loanClaimRedeem * loanClaimPeriods;
        require(sti.allowance(msg.sender, address(this)) >= loanClaimMinApproval);
        require(creditClaims[_claimId].loanAmount >= _amount);
        require(creditClaims[_claimId].claimLastTo >= now);
        
        uint creditor = getSenderId(msg.sender);
        uint creditReceiverId = creditClaims[_claimId].borrowersId;
        
        uint claimedLoanLength = creditClaims[_claimId].loanLength;
        uint amountToBorrower = _amount * 995 / 1000;
        uint amountToMC2 = _amount * 5 / 1000;
        sti.transferFrom(msg.sender, address(this), _amount);
        sti.transfer(creditClaims[_claimId].borrowersAddress, amountToBorrower); 
        sti.transfer(MC2Address, amountToMC2);
        creditClaims[_claimId].loanAmount -= _amount;
        
        TestCreditContract newCredit = new TestCreditContract(creditCounter, creditor, creditReceiverId, _amount, paybacksInterest, loanClaimPeriods, loanClaimRedeem, claimedLoanLength, address(this));
        tui.setCreditContractAddress(address(newCredit), creditReceiverId, creditCounter);
        creditCounter = Credits.push(address(newCredit));
        emit NewCredit(address(newCredit));
    }
    
    function redeem(uint _creditId) public onlyServer {
        TestCreditContract credit = TestCreditContract(Credits[_creditId]);
        //AgreementInterface ncredit = AgreementInterface(Credits[_creditId]);
        uint lastRedeem = credit.lastReedem();
        uint redeemPeriods = credit.periods();
        require(redeemPeriods > lastRedeem);
        require(now >= credit.loanExpiration(lastRedeem + 1));
        address borrower = tui.getUsersAddress(credit.borrowerId(), 0); 
        uint paybackAmount = credit.toPayBack();
        uint currentCapital = credit.capital();
        uint loansInterestRate = credit.interestRate();
        uint currentInterest = uint(currentCapital * loansInterestRate / 100);
        uint changeCapital = paybackAmount - currentInterest;
        
        address ownerOfLendingContract = credit.owner();
        uint fee = uint(currentInterest / 10);
        uint MC2Part;
        if(fee >= 1) {
            MC2Part = fee;
        } else {
            MC2Part = 1;
        }
        uint ownerRedeemPart = paybackAmount - MC2Part;
        if(sti.getTokenBalance(borrower) >= paybackAmount) {
            sti.transferFrom(borrower, ownerOfLendingContract, ownerRedeemPart, loansInterestRate, true);
            sti.transferFrom(borrower, MC2Address, MC2Part, loansInterestRate, true);
            credit.setToRedeemed(changeCapital);
            paybackAmount = 0;   
        } else {
            credit.latePayment();
        }
    }
    
    //Reuseable, should be in custom contract/library
    
    function calcRedeem (uint _amount, uint _period, uint _rate) private pure returns(uint) { 
        uint pow = 1;
        uint onePerPow = 1000000000000;
        uint ratePlus = _rate + 100;
        if(_period == 1) {
            pow *= ratePlus * 100;
        } else {
            for(uint i = 1; i <= _period; i++) {
                pow *= ratePlus;
                if(i > 2) {
                    pow /= 100; 
                }
            }
        }
        onePerPow /= pow;
        uint oneMinus = 100000000 - onePerPow;
        uint currentRedeem = uint(_amount * _rate * 1000000 / oneMinus);
        return(currentRedeem);
    }
}
