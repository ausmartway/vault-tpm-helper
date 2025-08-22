# instructions for claude

need a test plan for this project, the test will:

1. scp the latest build to a linux host tpmtest
2. ssh into the tpmtest host and run the tests
    a. test with a tpm protected key
    b. test with a normal key

the tests should verify that the application behaves as expected in both
scenarios, and that the tpm protected key is properly utilized.

the test will envolve a test vault server, below are the enviroment
variables it needs:

1. VAULT_ADDR: The address of the Vault server, set to `https://nginx`

2. VAULT_TOKEN: The root token to get a new pair of key/certifcate from
   pki_intermediate/role/machine-id, the token is
   "hvs.mjvXxeTkNJLbcO3rYItDjaXX"
