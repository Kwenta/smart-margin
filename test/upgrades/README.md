# Upgrade Testing

## Methodology

- Define the *new* interface which will be used in the upgrade
> see `v2.1.1/interfaces/IAccount`
- Import the *old* being used at the specific block number that is used for forking the environment
- Modify all possible state in an existing account (i.e. deploy one and then modify it in every way possible)
> this is to sanity check no storage slots are overwritten
- Deploy a new contract that uses the new interface
- Upgrade the SMv2 system via a call to the Factory to upgrade the implementation
- Check all state is still correct

## Compatability

- If written properly, all older tests for upgrades should work
- State should **ONLY** be introduced and **NEVER** rearranged or removed. 
- Even with introducing state, it should be done in a way that is backwards compatible with the old state (i.e. appended)