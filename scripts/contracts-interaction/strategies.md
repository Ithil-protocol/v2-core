# How to interact with Services

# step 0

deploy service set Cap for each token | WETH

# step 1

Open position

```
open(Order order) ???
```

struct Order { Agreement agreement; bytes data; // empty }

struct Agreement { Loan[] loans; Collateral[] collaterals; uint256 createdAt; // 0, not used Status status; // 0, not
used }

Loan0 - offer 1 WETH, loan 2 WETH = total 3 WETH struct Loan { address token; // WETH uint256 amount; // 2 _ 10^18
uint256 margin; // 1 _ 10^18 uint256 interestAndSpread; // 0 }

How to calculate amount? Call AAVE service and calculate aWETH amount

struct Collateral { ItemType itemType; // ERC20 - 0 address token; // aWETH uint256 identifier; // 0, only on NFT,
tokenId uint256 amount; // ratio given by AAVE }

# Retrieve positions

list all tokenId on specific user, base this on ERC721Enumerable

```
getAgreement(uint256)
```
