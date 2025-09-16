//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
    Stores all relevant information on all projects deployed through Enjoy Pump
 */

import "./interfaces/IDatabase.sol";
import "./interfaces/IBondingCurve.sol";
import "./interfaces/IEnjoyPumpGenerator.sol";
import "./interfaces/IEnjoyPumpVolumeTracker.sol";
import "./lib/EnumerableSet.sol";
import "./lib/Ownable.sol";
import "./lib/TransferHelper.sol";

contract EnjoyPumpDatabase is IDatabase, Ownable {

    // Project struct
    struct Project {
        address asset;
        address bondingCurve;
        string[] metadata; // social links, description, imageUrl
        address dev;
    }

    // Mapping of project nonce to project
    mapping (uint256 => Project) public projects;

    // Mapping of asset to project nonce
    mapping ( address => uint256 ) public assetToProject;

    // Maps a bonding curve to a token
    mapping ( address => address ) public bondingCurveToToken;

    // Maps an address to a list of projects they have launched
    mapping ( address => uint256[] ) public allDevProjects;

    // Master copy of the EnjoyPumpToken
    address internal enjoyPumpTokenMasterCopy;

    // Master copy of the EnjoyPumpBondingCurve
    address internal enjoyPumpBondingCurveMasterCopy;

    // EnjoyPumpGenerator
    address internal enjoyPumpGenerator;

    // Launch fee
    uint256 public launchFee;

    // Fee recipient
    address private feeRecipient;

    // Project nonce
    uint256 public projectNonce = 1;

    // Liquidity adder contract
    address public liquidityAdder;

    // Token Perma Locker
    address public liquidityPermaLocker;

    // EnjoyPump Volume Tracker
    address public enjoyPumpVolumeTracker;

    // List of all bonded projects
    EnumerableSet.UintSet private bondedProjects;

    // Lits of all pre-bonded projects
    EnumerableSet.UintSet private preBondedProjects;

    // Pauses all new launches
    bool public paused;

    // Event emitted when project is created
    event NewTokenCreated(address indexed dev, address token, address bondingCurve, uint nonce, bytes projectData);
    event Bonded(address token);

    constructor() {
        launchFee = 0 ether;
        feeRecipient = msg.sender;
        liquidityPermaLocker = 0x000000000000000000000000000000000000dEaD;
    }

    /**
        Sets the address of the EnjoyPumpTokenMasterCopy
     */
    function setEnjoyPumpTokenMasterCopy(address _enjoyPumpTokenMasterCopy) external onlyOwner {
        enjoyPumpTokenMasterCopy = _enjoyPumpTokenMasterCopy;
    }

    /**
        Sets Paused
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
        Sets the address of the EnjoyPumpBondingCurveMasterCopy
     */
    function setEnjoyPumpBondingCurveMasterCopy(address _enjoyPumpBondingCurveMasterCopy) external onlyOwner {
        enjoyPumpBondingCurveMasterCopy = _enjoyPumpBondingCurveMasterCopy;
    }

    /**
        Sets the address of the EnjoyPumpGenerator
     */
    function setEnjoyPumpGenerator(address _enjoyPumpGenerator) external onlyOwner {
        enjoyPumpGenerator = _enjoyPumpGenerator;
    }

    /**
        Sets the launch fee
     */
    function setLaunchFee(uint256 _launchFee) external onlyOwner {
        launchFee = _launchFee;
    }

    /**
        Sets the fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /**
        Sets the liquidity adder
     */
    function setLiquidityAdder(address _liquidityAdder) external onlyOwner {
        liquidityAdder = _liquidityAdder;
    }

    /**
        Sets the enjoyPump volume tracker
     */
    function setEnjoyPumpVolumeTracker(address _enjoyPumpVolumeTracker) external onlyOwner {
        enjoyPumpVolumeTracker = _enjoyPumpVolumeTracker;
    }

    /**
        Sets the token perma locker
     */
    function setLiquidityPermaLocker(address _liquidityPermaLocker) external onlyOwner {
        liquidityPermaLocker = _liquidityPermaLocker;
    }

    function registerVolume(address user, uint256 amount) external override {
        if (projects[assetToProject[bondingCurveToToken[msg.sender]]].bondingCurve != msg.sender) {
            return;
        }
        if (amount == 0 || user == address(0) || enjoyPumpVolumeTracker == address(0)) {
            return;
        }

        // register volume
        IEnjoyPumpVolumeTracker(enjoyPumpVolumeTracker).addVolume(user, amount);
    }

    function bondProject() external override {

        // fetch project from bonding curve
        uint256 projectID = assetToProject[bondingCurveToToken[msg.sender]];
        if (projects[projectID].bondingCurve != msg.sender || projectID == 0) {
            return;
        }

        // add to bonded projects
        EnumerableSet.add(bondedProjects, projectID);

        // remove from pre-bonded projects
        EnumerableSet.remove(preBondedProjects, projectID);

        // emit Bonded event
        emit Bonded(bondingCurveToToken[msg.sender]);
    }

    function launchProject(
        string[] calldata metadata,
        bytes calldata tokenPayload,
        bytes calldata bondingCurvePayload
    ) external payable returns (uint256) {
        require(
            !paused,
            'Paused'
        );
        // ensure fees are taken
        require(
            msg.value >= launchFee,
            'Insufficient Fee'
        );

        // send fee to fee recipient
        TransferHelper.safeTransferETH(feeRecipient, launchFee);

        // generate token and bonding curve
        (address token, address bondingCurve) = IEnjoyPumpGenerator(enjoyPumpGenerator).generateProject(tokenPayload, bondingCurvePayload, liquidityAdder);

        // store project
        projects[projectNonce] = Project({
            asset: token,
            bondingCurve: bondingCurve,
            metadata: metadata,
            dev: tx.origin
        });

        // store asset to project mapping
        assetToProject[token] = projectNonce;

        // store bonding curve to token launch
        bondingCurveToToken[bondingCurve] = token;

        // add to list
        EnumerableSet.add(preBondedProjects, projectNonce);

        // add to dev list
        allDevProjects[tx.origin].push(projectNonce);

        // emit new event
        emit NewTokenCreated(tx.origin, token, bondingCurve, projectNonce, abi.encode(metadata, tokenPayload, bondingCurvePayload));

        // increment nonce
        unchecked {
            ++projectNonce;
        }

        // if user supplied more value than launch fee, use it to buy tokens for them
        if (msg.value > launchFee) {
            IBondingCurve(bondingCurve).buyTokens{value: msg.value - launchFee}(msg.sender, 0);
        }

        return projectNonce - 1;
    }

    function getEnjoyPumpTokenMasterCopy() external view override returns (address) {
        return enjoyPumpTokenMasterCopy;
    }

    function getAllDevProjects(address dev) external view returns (uint256[] memory) {
        return allDevProjects[dev];
    }

    function getNumDevProjects(address dev) external view returns (uint256) {
        return allDevProjects[dev].length;
    }

    function getLatestDevProject(address dev) external view returns (uint256) {
        if (allDevProjects[dev].length == 0) {
            return 0;
        }
        return allDevProjects[dev][allDevProjects[dev].length - 1];
    }

    function getBondingCurveMasterCopy() external view override returns (address) {
        return enjoyPumpBondingCurveMasterCopy;
    }

    function getEnjoyPumpGenerator() external view override returns (address) {
        return enjoyPumpGenerator;
    }

    function isBonded(address token) external view override returns (bool) {
        return IBondingCurve(projects[assetToProject[token]].bondingCurve).isBonded();
    }

    function isBondedByID(uint256 projectID) external view returns (bool) {
        return IBondingCurve(projects[projectID].bondingCurve).isBonded();
    }

    function isEnjoyPumpToken(address token) external view override returns (bool) {
        return assetToProject[token] != 0 && projects[assetToProject[token]].asset == token;
    }

    function getBondingCurveForToken(address token) external view override returns (address) {
        return projects[assetToProject[token]].bondingCurve;
    }

    function getProjectMetadata(address token) external view returns (string[] memory) {
        return projects[assetToProject[token]].metadata;
    }

    function getProjectDev(address token) external view returns (address) {
        return projects[assetToProject[token]].dev;
    }

    function getLiquidityLocker() external view override returns (address) {
        return liquidityPermaLocker;
    }

    function getFeeRecipient() external view override returns (address) {
        return feeRecipient;
    }

    function getProjectInfoByToken(address token) public view returns (address, address, string[] memory, address) {
        Project memory project = projects[assetToProject[token]];
        return (project.asset, project.bondingCurve, project.metadata, project.dev);
    }

    function batchGetProjectInfoByTokens(address[] calldata tokens) external view returns (address[] memory, address[] memory, string[][] memory, address[] memory) {
        
        uint len = tokens.length;
        address[] memory assets = new address[](len);
        address[] memory bondingCurves = new address[](len);
        string[][] memory metadata = new string[][](len);
        address[] memory devs = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            ( assets[i], bondingCurves[i], metadata[i], devs[i] ) = getProjectInfoByToken(tokens[i]);
        }

        return (assets, bondingCurves, metadata, devs);
    }

    function batchGetProjectInfo(uint256[] calldata projectIDs) public view returns (address[] memory, address[] memory, string[][] memory, address[] memory) {
        
        uint len = projectIDs.length;
        address[] memory assets = new address[](len);
        address[] memory bondingCurves = new address[](len);
        string[][] memory metadata = new string[][](len);
        address[] memory devs = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            Project memory project = projects[projectIDs[i]];
            assets[i] = project.asset;
            bondingCurves[i] = project.bondingCurve;
            metadata[i] = project.metadata;
            devs[i] = project.dev;
        }

        return (assets, bondingCurves, metadata, devs);
    }

    function paginateBondedProjectIDs(uint256 startIndex, uint256 endIndex) external view returns (uint256[] memory) {
        if (endIndex > EnumerableSet.length(bondedProjects)) {
            endIndex = EnumerableSet.length(bondedProjects);
        }

        uint256 length = endIndex - startIndex;
        uint256[] memory projectIDs = new uint256[](length);
        for (uint256 i = startIndex; i < endIndex;) {
            projectIDs[i - startIndex] = EnumerableSet.at(bondedProjects, i);
            unchecked { ++i; }
        }
        return projectIDs;
    }

    function paginatePrebondedProjectIDs(uint256 startIndex, uint256 endIndex) public view returns (uint256[] memory) {
        if (endIndex > EnumerableSet.length(preBondedProjects)) {
            endIndex = EnumerableSet.length(preBondedProjects);
        }

        uint256 length = endIndex - startIndex;
        uint256[] memory projectIDs = new uint256[](length);
        for (uint256 i = startIndex; i < endIndex;) {
            projectIDs[i - startIndex] = EnumerableSet.at(preBondedProjects, i);
            unchecked { ++i; }
        }
        return projectIDs;
    }

    function paginatePrebondedProjects(uint256 startIndex, uint256 endIndex) external view returns(address[] memory, address[] memory, string[][] memory, address[] memory) {
        uint256[] memory projectIDs = paginatePrebondedProjectIDs(startIndex, endIndex);

        uint len = projectIDs.length;
        address[] memory assets = new address[](len);
        address[] memory bondingCurves = new address[](len);
        string[][] memory metadata = new string[][](len);
        address[] memory devs = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            Project memory project = projects[projectIDs[i]];
            assets[i] = project.asset;
            bondingCurves[i] = project.bondingCurve;
            metadata[i] = project.metadata;
            devs[i] = project.dev;
        }

        return (assets, bondingCurves, metadata, devs);
    }

    function numPrebondedProjects() external view returns (uint256) {
        return EnumerableSet.length(preBondedProjects);
    }

    function numBondedProjects() external view returns (uint256) {
        return EnumerableSet.length(bondedProjects);
    }
}