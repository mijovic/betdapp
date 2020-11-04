// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
// pragma experimental SMTChecker;
import "./token.sol";

enum BetType {
    FINAL_RESULT,
    EXACT_GOALS
}

enum FinalResultBets {
    DRAW,
    HOME_WIN,
    VISITOR_WIN
}

struct Result {
    uint16 home;
    uint16 visitor;
}

struct Game {
    string homeTeam;
    string visitorTeam;
    string competition;
    string livescoreLink;
    Result result;
}

struct Bet {
    address user;
    BetType betType;
    // in case of final result it is value of FinalResultBets enum
    // in case of exact goals is prediction of total goals in the game
    uint32 prediction;
    uint256 tokens;
}

contract Betster {
    BeToken m_tokenContract;
    address owner;
    uint256 currentGameId = 123456;
    uint256 multiplierToken;

    mapping(uint256 => Game) games;
    mapping(uint256 => mapping(uint32 => Bet[])) bets;
    mapping(uint256 => bool) activeGames;

    constructor(BeToken tokenContract) {
        m_tokenContract = tokenContract;
        multiplierToken = 10 ** m_tokenContract.decimals();
        owner = msg.sender;
    }

    function addGame(Game calldata game) public returns (uint256 gameId) {
        require(msg.sender == owner);
        gameId = currentGameId++;
        games[gameId] = game;
        activeGames[gameId] = true;
    }

    function stopBets(uint256 gameId) public {
        require(msg.sender == owner);
        activeGames[gameId] = false;
    }

    function placeBet(uint256 gameId, uint32 betType, uint32 prediction, uint256 tokens) public returns (bool) {
        uint256 actualTokens = tokens * multiplierToken;
        require(activeGames[gameId]);
        require(m_tokenContract.balanceOf(msg.sender) > actualTokens);
        m_tokenContract.transfer(owner, actualTokens);
        bets[gameId][betType].push(Bet(msg.sender, BetType(betType), prediction, actualTokens));
        return true;
    }

    function declareResult(uint256 gameId, Result calldata result) public {
        require(msg.sender == owner);
        // we need to get all the bets for this game
        // and transfer tokens to winner bets
        // the game to be fair, we can't mix types of bets, so we will spread tokens for final result to all the winners
        // plus tokens for exact goals to all winners
        // if no winner, tokens will be returned to user

        // so, we go with exact goals
        uint32 totalGoals = result.home + result.visitor;
        spreadToWinners(gameId, BetType.EXACT_GOALS, totalGoals);

        // than, go with final result bets
        FinalResultBets finalResult = 
            result.home > result.visitor ? 
            FinalResultBets.HOME_WIN : 
            (result.home < result.visitor ? FinalResultBets.VISITOR_WIN : FinalResultBets.DRAW);
        spreadToWinners(gameId, BetType.FINAL_RESULT, uint32(finalResult));
    }

    function spreadToWinners(uint256 gameId, BetType betType, uint32 winnerPrediction) internal {
        Bet[] storage betsPtr = bets[gameId][uint32(betType)];
        Bet[] memory winnerBets = new Bet[](betsPtr.length);
        uint256 totalWinners = 0;
        uint256 totalWinnerTokens = 0;
        uint256 totalTokens = 0;
        for (uint256 i = 0; i < betsPtr.length; ++i) {
            totalTokens += betsPtr[i].tokens;
            if (betsPtr[i].betType == BetType.EXACT_GOALS) {
                if (betsPtr[i].prediction == winnerPrediction) {
                    winnerBets[totalWinners++] = betsPtr[i];
                    totalWinnerTokens += betsPtr[i].tokens / multiplierToken;
                }
            }
        }

        if (totalWinners == 0) {
            assert(totalWinnerTokens == 0);
            for (uint256 i = 0; i < betsPtr.length; ++i) {
                m_tokenContract.transfer(betsPtr[i].user, betsPtr[i].tokens);
            }
        } else {
            assert(totalWinnerTokens > 0);
            uint256 valuePerWinningToken = totalTokens / totalWinnerTokens;
            for (uint256 i = 0; i < winnerBets.length; ++i) {
                m_tokenContract.transfer(winnerBets[i].user, winnerBets[i].tokens * valuePerWinningToken * multiplierToken);
            }
        }
    }
}
