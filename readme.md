# Smart-escrow contracts
Baked with <3 by [Jincor](https://ico.jincor.com)

## Smart-escrow

This contract should receive money from investors(crowdsale) and control phased money spendings raised during token sale by the team. Each next tranche of ETH to the team is allowed only after approval of previous phases by the team with the documents and according to the roadmap.

Settings:
1. Voting round length
2. Min number of tokens required for the vote
3. Percent of positive votes required to succeed(calculated based on fact amount of voters)
4. Voting reason
5. Message
6. Value < this.balance


New voting round can be initiated from admin panel. New vote round can be initiated only after approval documentation uploaded

If round succeed we must send the corresponding value of ETH to the team. If failed - ETH should be available to withdraw by token holders `R = (ETH / A) * V `.

R - reward

ETH - amount of ETH tranche Value

A - total supply of all tokens

V - amount of tokens on holders balance

## How to setup development environment and run tests?

1. Install `docker` if you don't have it.
1. Clone this repo.
1. Run `docker-compose build --no-cache`.
1. Run `docker-compose up -d`.
1. Install dependencies: `docker-compose exec workspace yarn`.
1. To run tests: `docker-compose exec workspace truffle test`.
1. To merge your contracts via sol-merger run: `docker-compose exec workspace yarn merge`.
Merged contracts will appear in `merge` directory.
