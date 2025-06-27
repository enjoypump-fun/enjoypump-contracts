//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
    Launched Per Project, simulates a bonding curve for tokens to be locked and released as users buy and sell
    Once this contract reaches the desired number of NATIVE Tokens specified by the Database, it will interact with the LiquidityAdder
    To add Tokens and Liquidity into the desired DEX
 */

import "./interfaces/IICOBondingCurve.sol";
import "./interfaces/IEnjoyPumpToken.sol";
import "./interfaces/ILiquidityAdder.sol";
import "./interfaces/IFeeRecipient.sol";
import "./interfaces/IDatabase.sol";
import "./lib/EnumerableSet.sol";
import "prb-math/contracts/PRBMathUD60x18.sol";

contract BondingCurveData {
    uint32 internal versionNo;
    address internal token;
    address internal liquidityAdder;

    address internal icoManager;

    bool public isICOActive;

    bool internal bonded;
    uint256 public constant BONDING_TARGET = 800_000_000 * 10**18;
    uint256 public constant TOKEN_TOTAL = 1_000_000_000 * 10**18;

    // aScaled = 0.000000001 * 1e18
    uint256 public constant A_SCALED = 0.000000001 ether;

    // bScaled = 0.0000000034 * 1e18
    uint256 public constant B_SCALED = 0.0000000034 ether;// 0.0000000034 ether;

    // total supply of tokens in the bonding curve
    uint256 public bondingSupply;

    // trade fee
    uint8 public tradeFee;

    // total volume
    uint256 public totalVolume;

    // max supply per wallet
    uint256 public maxSupplyPerWallet;

    // keep log of trades
    struct Trade {
        address maker;
        int256 ethAmount;
        int256 tokenAmount;
        uint256 currentSupply;
        uint256 timestamp;
    }

    // trade nonce
    uint256 public tradeNonce;

    // mapping of trade nonce to trade
    mapping (uint256 => Trade) public trades;

    // Holder list
    EnumerableSet.AddressSet internal holders;

    // Buy Event
    event ICOBuy(uint256 quantityETH, uint256 quantityTokens);
    event Buy(address indexed user, uint256 quantityETH, uint256 quantityTokens);
    event Sell(address indexed user, uint256 quantityETH, uint256 quantityTokens);
}

contract ICOBondingCurve is BondingCurveData, IICOBondingCurve {

    using PRBMathUD60x18 for uint256;

    function __init__(bytes calldata payload, address token_, address liquidityAdder_, address icoManager_) external override {
        require(token == address(0), 'Already Initialized');
        require(token_ != address(0), 'Zero Address');
        (
            versionNo,
            maxSupplyPerWallet
        ) = abi.decode(payload, (uint32, uint256));
        token = token_;
        liquidityAdder = liquidityAdder_;
        bonded = false;
        bondingSupply = 0;
        tradeFee = 20; // 2%
        icoManager = icoManager_;
        isICOActive = true;
    }


    function startTrading() external override payable returns (uint256 tokensBought) {
        require(msg.sender == icoManager, 'Not ICO Manager');
        require(isICOActive, 'ICO Not Active');
        require(!bonded, 'Already Bonded');

        // turn off ICO
        isICOActive = false;

        // if no value sent, return
        if (msg.value == 0) {
            return 0;
        }

        // buy tokens for ICO
        // determine eth in value from trade fee
        uint256 ethIn = _takeICOFee(msg.value);

        // Determine the desired ΔS (in 1e18 scale) from the ETH sent.
        tokensBought = solveIntegralBuy(bondingSupply, ethIn);

        // Determine the remaining tokens available.
        uint256 remainingTokens = BONDING_TARGET - bondingSupply;

        // If the desired purchase exceeds the remaining supply,
        // clamp tokensBought to the remaining amount.
        if (tokensBought > remainingTokens) {

            // Update the tokens bought to the remaining amount.
            tokensBought = remainingTokens;

            // Compute the actual cost (in 1e18 scale) for tokensBought using the forward integral:
            // costForward = (a/b) * (e^(b*(S + ΔS)) - e^(b*S))
            uint256 actualCostScaled = costForward(bondingSupply, tokensBought);

            // Ensure that the user sent at least the actual cost.
            require(ethIn >= actualCostScaled, "Not enough ETH sent");

            // Update state: add the tokens bought.
            unchecked {
                bondingSupply += tokensBought;
            }

            // Mint tokens to the buyer.
            _mint(icoManager, tokensBought);

            // Refund any ETH not used in the purchase.
            uint256 refund = ethIn - actualCostScaled;

            // bond the contract, sending necessary funds to fee receiver and dex
            _bond(address(this).balance - refund);
            
            // Refund any excess ETH
            if (refund > 0) {
                // take fee
                IFeeRecipient(ILiquidityAdder(liquidityAdder).getFeeRecipient()).takeVolumeFee{value: refund}(token);
            }

        } else {

            // Update state: add the tokens bought.
            unchecked {
                bondingSupply += tokensBought;
            }

            // Mint tokens to the buyer.
            _mint(icoManager, tokensBought);

            // see if bonded
            if (bondingSupply >= BONDING_TARGET) {
                _bond(address(this).balance);
            }
        }

        // emit event
        emit ICOBuy(ethIn, tokensBought);

        // log trade
        trades[tradeNonce] = Trade({
            maker: icoManager,
            ethAmount: int256(ethIn) * int256(-1),
            tokenAmount: int256(tokensBought),
            currentSupply: bondingSupply, 
            timestamp: block.timestamp
        });

        // increment trade nonce
        unchecked {
            ++tradeNonce;
        }

        return tokensBought;
    }


    // --------------------------------------------------------------------------------
    // Public BUY: user sends ETH => get newly minted tokens
    // --------------------------------------------------------------------------------

    /**
    * @notice Buy tokens from the bonding curve by sending ETH.
    *         If the ETH provided would purchase more tokens than remain,
    *         then only the remaining tokens are bought and any extra ETH is refunded.
    * @dev Uses the forward integral to calculate cost.
    */
    function buyTokens(address recipient, uint256 minOut) external payable override returns (uint256 tokensBought) {
        require(msg.value > 0, "No ETH sent");
        require(bondingSupply < BONDING_TARGET, "Bonding curve is full");
        require(!bonded, "Bonding curve is bonded");
        require(isICOActive == false, "ICO is still active");

        // determine eth in value from trade fee
        uint256 ethIn = _takeFee(recipient, msg.value);

        // Determine the desired ΔS (in 1e18 scale) from the ETH sent.
        tokensBought = solveIntegralBuy(bondingSupply, ethIn);

        // Determine the remaining tokens available.
        uint256 remainingTokens = BONDING_TARGET - bondingSupply;

        // If the desired purchase exceeds the remaining supply,
        // clamp tokensBought to the remaining amount.
        if (tokensBought > remainingTokens) {

            // Update the tokens bought to the remaining amount.
            tokensBought = remainingTokens;

            // Compute the actual cost (in 1e18 scale) for tokensBought using the forward integral:
            // costForward = (a/b) * (e^(b*(S + ΔS)) - e^(b*S))
            uint256 actualCostScaled = costForward(bondingSupply, tokensBought);

            // Ensure that the user sent at least the actual cost.
            require(ethIn >= actualCostScaled, "Not enough ETH sent");

            // Update state: add the tokens bought.
            unchecked {
                bondingSupply += tokensBought;
            }

            // Mint tokens to the buyer.
            _mint(recipient, tokensBought);

            // Refund any ETH not used in the purchase.
            uint256 refund = ethIn - actualCostScaled;

            // bond the contract, sending necessary funds to fee receiver and dex
            _bond(address(this).balance - refund);
            
            // Refund any excess ETH
            if (refund > 0) {
                (bool success, ) = payable(recipient).call{value: refund}("");
                require(success, "Refund failed");
            }

        } else {

            // ensure minOut is enforced
            require(
                tokensBought >= minOut,
                'Too Few Tokens Received, Increase Slippage'
            );

            // Update state: add the tokens bought.
            unchecked {
                bondingSupply += tokensBought;
            }

            // Mint tokens to the buyer.
            _mint(recipient, tokensBought);

            // see if bonded
            if (bondingSupply >= BONDING_TARGET) {
                _bond(address(this).balance);
            }
        }

        // emit event
        emit Buy(recipient, ethIn, tokensBought);

        // log trade
        trades[tradeNonce] = Trade({
            maker: msg.sender,
            ethAmount: int256(ethIn) * int256(-1),
            tokenAmount: int256(tokensBought),
            currentSupply: bondingSupply, 
            timestamp: block.timestamp
        });

        // increment trade nonce
        unchecked {
            ++tradeNonce;
        }

        return tokensBought;
    }

    // --------------------------------------------------------------------------------
    // Public SELL: user burns tokens => receive ETH
    // --------------------------------------------------------------------------------

    /**
     * @notice Sell tokens back to the bonding curve for ETH. We integrate forward to find how much ETH.
     * @param tokenAmount The number of tokens (1e18 scale) the user wants to sell.
     */
    function sellTokens(uint256 tokenAmount) external returns (uint256 ethOutWei) {
        require(tokenAmount > 0, "No tokens to sell");
        require(balanceOf(msg.sender) >= tokenAmount, "Not enough tokens");
        require(!bonded, "Bonding curve is bonded");
        require(isICOActive == false, "ICO is still active");

        // Cap at how many the user can actually sell from the curve standpoint
        require(tokenAmount <= bondingSupply, "Too many tokens sold?");

        // compute how much ETH we owe them in 1e18 scale
        ethOutWei = solveIntegralSell(bondingSupply, tokenAmount);

        // burn the tokens
        _burn(msg.sender, tokenAmount);

        // update supply
        unchecked {
            bondingSupply -= tokenAmount;
        }

        // emit event
        emit Sell(msg.sender, ethOutWei, tokenAmount);

        // log trade
        trades[tradeNonce] = Trade({
            maker: msg.sender,
            ethAmount: int256(ethOutWei),
            tokenAmount: int256(tokenAmount) * int256(-1),
            currentSupply: bondingSupply,
            timestamp: block.timestamp
        });

        // increment trade nonce
        unchecked {
            ++tradeNonce;
        }

        // take fee
        uint256 ethOut = _takeFee(msg.sender, ethOutWei);

        // send ETH
        (bool success, ) = payable(msg.sender).call{value: ethOut}("");
        require(success, "ETH transfer failed");
    }

    // --------------------------------------------------------------------------------
    // Preview / Helper functions
    // --------------------------------------------------------------------------------

    /**
     * @notice Preview how many tokens you'd get by sending `ethAmountWei` wei.
     * @param ethAmountWei The amount of ETH in wei to buy with.
     * @return tokensBought in 1e18 scale
     */
    function previewBuy(uint256 ethAmountWei) external view returns (uint256) {
        if (ethAmountWei == 0) return 0;

        // Convert to scaled
        return solveIntegralBuy(bondingSupply, ethAmountWei);
    }

    /**
     * @notice Preview how much ETH (in wei) you'd get for selling `tokenAmount` tokens.
     * @param tokenAmount The token amount in 1e18 scale.
     * @return ethOutWei The resulting ETH in wei.
     */
    function previewSell(uint256 tokenAmount) external view returns (uint256) {
        if (tokenAmount == 0) return 0;
        return solveIntegralSell(bondingSupply, tokenAmount);
    }

    // --------------------------------------------------------------------------------
    // Internal Integral Math
    // Using p(S)= a*exp(b*S). Then:
    //
    //   Buy cost = ∫ p(s) ds from s=S..S+ΔS
    //            = (a/b)*( e^{b(S+ΔS)} - e^{bS} ).
    // We invert that to solve ΔS from costIn.
    //
    //   Sell return = ∫ p(s) ds from s=S-ΔS..S
    //               = (a/b)*( e^{bS} - e^{b(S-ΔS)} ).
    //
    // a,b in 1e18 scale. S also in 1e18 scale. We do the exponent in UD60x18.
    // --------------------------------------------------------------------------------


    /**
    * @dev Compute the forward integral (cost) to purchase an additional _deltaS tokens,
    * starting from a current supply _S.
    *
    * Formula: costForward = (a / b) * (e^(b * (S + deltaS)) - e^(b * S))
    * where a = A_SCALED and b = B_SCALED (both scaled by 1e18).
    *
    * All parameters are in 1e18 fixed-point.
    */
    function costForward(uint256 _S, uint256 _deltaS)
        public
        pure
        returns (uint256 cost)
    {
        // Compute b * (S + deltaS) in 1e18 scale.
        uint256 bTimesSplusDelta = B_SCALED.mul(_S + _deltaS).div(1e18);
        // Compute b * S in 1e18 scale.
        uint256 bTimesS = B_SCALED.mul(_S).div(1e18);

        // Compute exponentials: exp(b*(S + deltaS)) and exp(b*S).
        uint256 expHigh = bTimesSplusDelta.exp(); // e^(b*(S+deltaS))
        uint256 expLow = bTimesS.exp();           // e^(b*S)

        // The difference: e^(b*(S+deltaS)) - e^(b*S)
        uint256 diff = expHigh > expLow ? expHigh - expLow : 0;

        // Calculate (a / b) in 1e18 scale.
        // aOverB = A_SCALED * 1e18 / B_SCALED ensures the ratio is scaled properly.
        uint256 aOverB = A_SCALED.mul(1e18).div(B_SCALED);

        // Multiply the ratio by the difference and scale back down.
        cost = aOverB.mul(diff).div(1e18);
    }

    /**
     * @dev Solve for deltaS in the "buy" integral inversion:
     *      costIn = (a/b)*( e^{b(S+deltaS)} - e^{bS} )
     * =>   e^{b(S+deltaS)} = e^{bS} + (b/a)*costIn
     * =>   b(S+deltaS) = ln( e^{bS} + (b/a)*costIn )
     * =>   deltaS = (1/b)*ln( e^{bS} + (b/a)*costIn ) - S
     *
     * @param _currentSupply S (1e18 scale)
     * @param _costInScaled  costIn in 1e18 scale (i.e. ETH "units" at 1e18 = 1 ETH).
     * @return deltaS in 1e18 scale
     */
    function solveIntegralBuy(uint256 _currentSupply, uint256 _costInScaled)
        public
        pure
        returns (uint256 deltaS)
    {
        if (_costInScaled == 0) {
            return 0;
        }

        // e^(b*S)
        // Using PRBMath's UD60x18: "mul(x,y)" => (x*y)/1e18. "exp(x)" => e^x in 1e18.
        uint256 bS = B_SCALED.mul(_currentSupply); // (b * S) in 1e18
        uint256 exp_bS = bS.exp();                // e^(bS) in 1e18

        // (b/a)*costIn
        // b/a => (bScaled * 1e18 / aScaled) if we want 1e18 scale, or simply do mulDiv
        // but let's do it step by step:
        // ratio = bScaled.div(A_SCALED) => (b/a) in 1e18
        // then multiply by costIn => ratio.mul(_costInScaled)
        uint256 bOverA = PRBMathUD60x18.div(B_SCALED, A_SCALED); //B_SCALED.div(1e18, A_SCALED); // = (bScaled * 1e18)/aScaled in 1e18
        uint256 term = bOverA.mul(_costInScaled);        // => (b/a)*costIn in 1e18

        // inside = e^(bS) + (b/a)*costIn
        uint256 inside = exp_bS + term;

        // ln(inside)
        uint256 lnInside = inside.ln();

        // b*(S+deltaS) = ln( inside )
        // => S+deltaS = ln(inside)/b
        // => deltaS = ln(inside)/b - S
        // but watch out for scale: "ln(inside)" is 1e18, b is 1e18 => dividing => result is 1e18
        uint256 oneOverB = uint256(1e18).div(B_SCALED); // 1/b in 1e18
        uint256 SplusDelta = oneOverB.mul(lnInside);    // ln(inside)/b in 1e18

        // deltaS = SplusDelta - S
        // both are 1e18 scale
        if (SplusDelta > _currentSupply) {
            deltaS = SplusDelta - _currentSupply;
        } else {
            // If for some reason it underflows (unlikely in normal usage),
            // just return 0 to avoid revert.
            deltaS = 0;
        }
    }

    /**
     * @dev Solve how much ETH is returned if user sells 'tokenAmount':
     *      return = ∫ p(s) ds from s=(S - tokenAmount)..S
     *             = (a/b)*( e^{bS} - e^{b(S - tokenAmount)} )
     *
     * @param _currentSupply S in 1e18
     * @param _tokenAmount   ΔS in 1e18
     * @return ethOut in 1e18 scale
     */
    function solveIntegralSell(uint256 _currentSupply, uint256 _tokenAmount)
        public
        pure
        returns (uint256)
    {
        if (_tokenAmount == 0) {
            return 0;
        }
        // e^(bS)
        uint256 bS = B_SCALED.mul(_currentSupply);
        uint256 exp_bS = bS.exp();

        // e^( b*(S - tokenAmount) )
        uint256 b_S_minus_dS = B_SCALED.mul(_currentSupply - _tokenAmount);
        uint256 expTerm = b_S_minus_dS.exp();

        // difference = e^(bS) - e^(b(S - deltaS))
        uint256 diff = exp_bS > expTerm ? exp_bS - expTerm : 0;

        // multiply by (a/b)
        // a/b => aScaled div bScaled in 1e18
        uint256 aOverB = PRBMathUD60x18.div(A_SCALED, B_SCALED); //A_SCALED.mulDiv(1e18, B_SCALED);
        uint256 ethScaled = aOverB.mul(diff); // => (a/b)*( e^(bS) - e^(b(S - dS)) ) in 1e18

        return ethScaled;
    }

    function _mint(address to, uint256 amount) internal {
        if (IEnjoyPumpToken(token).balanceOf(to) == 0 && amount > 0) {
            EnumerableSet.add(holders, to);
        }

        IEnjoyPumpToken(token).transfer(to, amount);

        // if this wallet has more than the max per wallet, revert
        if (maxSupplyPerWallet > 0) {
            require(
                IEnjoyPumpToken(token).balanceOf(to) <= maxSupplyPerWallet,
                "Max Supply Per Wallet Exceeded"
            );
        }
    }

    function _burn(address from, uint256 amount) internal {
        IEnjoyPumpToken(token).bondingCurveTransferFrom(from, address(this), amount);

        if (IEnjoyPumpToken(token).balanceOf(from) == 0 && EnumerableSet.contains(holders, from)) {
            EnumerableSet.remove(holders, from);
        }
    }

    function _bond(uint256 ethAmount) internal {

        // set bonded
        bonded = true;

        // transfer tokens to liquidity adder
        IERC20(token).transfer(liquidityAdder, TOKEN_TOTAL - BONDING_TARGET);

        // bond project in database
        IDatabase(ILiquidityAdder(liquidityAdder).getDatabase()).bondProject();

        // bond for dex
        ILiquidityAdder(liquidityAdder).bond{value: ethAmount}(token);
    }

    function _takeFee(address user, uint256 amount) internal returns (uint256) {

        // split fee
        uint256 fee = ( amount * tradeFee ) / 1000;

        // take fee
        IFeeRecipient(ILiquidityAdder(liquidityAdder).getFeeRecipient()).takeVolumeFee{value: fee}(token);

        // log value
        IDatabase(ILiquidityAdder(liquidityAdder).getDatabase()).registerVolume(user, amount);

        // track our own volume
        unchecked {
            totalVolume += amount;
        }

        // return amount less fees
        return amount - fee;
    }

    function _takeICOFee(uint256 amount) internal returns (uint256) {

        // split fee
        uint256 fee = ( amount * tradeFee ) / 1000;

        // take fee
        if (fee > 0) {
            IFeeRecipient(ILiquidityAdder(liquidityAdder).getFeeRecipient()).takeVolumeFee{value: fee}(token);
        }

        // track our own volume
        unchecked {
            totalVolume += amount;
        }

        // return amount less fees
        return amount - fee;
    }

    function batchTrades(uint256 startIndex, uint256 endIndex) external view returns (Trade[] memory) {
        if (endIndex > tradeNonce) {
            endIndex = tradeNonce;
        }
        Trade[] memory _trades = new Trade[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex;) {
            _trades[i - startIndex] = trades[i];
            unchecked { ++i; }
        }
        return _trades;
    }

    function getListOfTrades(uint256[] calldata indexes) external view returns (Trade[] memory) {
        uint len = indexes.length;
        Trade[] memory _trades = new Trade[](len);
        for (uint256 i = 0; i < len;) {
            _trades[i] = trades[indexes[i]];
            unchecked { ++i; }
        }
        return _trades;
    }


    function getEvenlySplitPriceChanges(uint256 numDataPoints) external view returns (Trade[] memory) {
        if (numDataPoints > tradeNonce) {
            numDataPoints = tradeNonce;
        }

        // create array of trades
        Trade[] memory _trades = new Trade[](numDataPoints);

        // add all trades except most recent
        for (uint256 i = 0; i < numDataPoints - 1;) {
            _trades[i] = trades[( i * tradeNonce ) / ( numDataPoints - 1 )];
            unchecked { ++i; }
        }

        // add most recent trade
        _trades[numDataPoints - 1] = trades[tradeNonce - 1];

        return _trades;
    }

    function balanceOf(address user) public view returns (uint256) {
        return IEnjoyPumpToken(token).balanceOf(user);
    }

    /**
        * @dev Check if an account is allowed to transfer tokens before the bonding curve is reached
        * @param account address to check
        * @return bool if the account is allowed to transfer tokens, limited to bonding curve and liquidity adder
     */
    function allowEarlyTransfer(address account) external view returns (bool) {
        return account == address(this) || account == liquidityAdder || account == icoManager;
    }

    function getVersionNo() external view override returns (uint32) {
        return versionNo;
    }

    function isBonded() external view override returns (bool) {
        return bonded;
    }    

    function getToken() external view override returns (address) {
        return token;
    }

    function getHolders() external view returns (address[] memory) {
        return EnumerableSet.values(holders);
    }

    function getNumHolders() external view returns (uint256) {
        return EnumerableSet.length(holders);
    }

    function paginateHolders(uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        if (endIndex > EnumerableSet.length(holders)) {
            endIndex = EnumerableSet.length(holders);
        }
        address[] memory _holders = new address[](endIndex - startIndex);
        for (uint i = startIndex; i < endIndex;) {
            _holders[i - startIndex] = EnumerableSet.at(holders, i);
            unchecked { ++i; }
        }
        return _holders;
    }

    function paginateHoldersAndBalances(uint256 startIndex, uint256 endIndex) external view returns (address[] memory, uint256[] memory) {
        if (endIndex > EnumerableSet.length(holders)) {
            endIndex = EnumerableSet.length(holders);
        }
        address[] memory _holders = new address[](endIndex - startIndex);
        uint256[] memory balances = new uint256[](endIndex - startIndex);
        for (uint i = startIndex; i < endIndex;) {
            address holder = EnumerableSet.at(holders, i);
            _holders[i - startIndex] = holder;
            balances[i - startIndex] = IEnjoyPumpToken(token).balanceOf(holder);
            unchecked { ++i; }
        }
        return ( _holders, balances );
    }

    function viewAllHoldersAndBalances() external view returns (address[] memory, uint256[] memory) {
        uint256 length = EnumerableSet.length(holders);
        uint256[] memory balances = new uint256[](length);
        for (uint i = 0; i < length;) {
            balances[i] = IEnjoyPumpToken(token).balanceOf(EnumerableSet.at(holders, i));
            unchecked { ++i; }
        }
        return ( EnumerableSet.values(holders), balances );
    }
}