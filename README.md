# Bitwarden SSH key storage

Decided to test if [bitwarden](https://bitwarden.com/) could be used as a centralized encrypted storage for SSH keys, so created a wrapper script for generating & fetching SSH keys
to/from bitwarden vault. The idea is that the SSH key would never recide on the machine disk, but is created by using named pipe and then inputted to bitwarden
for safe keeping.

The script here is a quite simple bash script, there might be better ways to achieve this, but I decided to take the easy way out and just wrap the bitwarden 
cli with this script. I've tested the script to be somewhat functioning in MacOS Mojave and Ubuntu, but as always there might be issues

## Prerequisites

To use this you will need to have following packages installed
* bitwarden account
* bitwarden cli (https://github.com/bitwarden/cli)
* jq
* ssh tools

## Usage

```
Usage: ./bw_ssh_key.sh <list|generate|get_key|get_public_key> [-k key_name] [-t ttl] [-e encryption_type]
	list		List keys in vault
	search		Search for key name, useful if there are more than one matches
	generate	Generate new key to vault
	get_key		Get private key to ssh-agent
	get_public_key	get public key for the specified key
	-k|--key-name	Name for key, required for generating key or getting the key
	-i|--id		Use key ID to fetch the key
	-n|--no-prefix	Do not add key prefix (used for fetching keys from entries not added with this tool)
	-t|--ttl	How long private key should exist in agent, uses ssh-agent ttl syntax
	-e|--key-enc	Key type, accepts rsa or ed25519
	All required parameters will be asked unless specified with switch
```

The script currently allows for 
* key creation

   Key creation requires both key name and key encryption type. The key name will be prefixed with string `bw_ssh_` to allow easier listing of the items
   but when entering the key name you may omit that as it will be added automatically. 

   For the encryption alorithm you may choose either RSA or ED25519. The RSA keys will always be 4096 bit keys, ED25519 keys will use the fixed length
   ssh-keygen uses for them.

   both key name and encryption alogrithm will be asked if they are not specified with command line switches
   
   The keys will be added as secure notes and the note will contain both private and public key. The generation does not allow for additional password
   to be added for the key as the idea is that the bitwarden vault encryption would suffice.

* fetching the key to ssh-agent

  When fetching the key to ssh-agent you need to specify the key name or key ID. As with creation, the prefix `bw_ssh_` for key name will be automatically added, so you can
  omit that. You may also specify a time to live value for the key, if you wish to change the default one hour.

* printing out public key
  
  Similarly to fetching the private key, you need to specify key name and you may omit the `bw_ssh_` prefix. This command does not need or use other
  switches.

* listing keys in the vault
  Lists all entries in the vault that begin with the prefix `bw_ssh_`

* searching for keys
  Searches for keys based on key_name, useful if you have several similarly named keys. Will output both key name and key id. Search is case insensitive.

### Login / unlock

If you're using bitwarden cli for the first time on your machine the script will attempt to do a `login` -action when it is run for the first time.
For the consecutive runs it will check if you have already logged in and if so, it will only do an `unlock` -action for the vault. If specify the 
BW_SESSION -environment variable and the script will use that and will not ask for password. The script will also do a `sync` action with every run
to ensure that all keys are available.

### Known issues

When fetching keys from the vault, the script does a `get` action and that requires that the key name is unique enough. This means that if you have keys
`my_key` and `my_key2`, you can fetch `my_key2`, but fetching `my_key` will fail due to the fact that the search for it will find two entries for `my_key`
As a workaround, you should attempt to use names that will not collide like that. If you do have two colliding keys, you can always use the key ID to 
fetch the key (use list or search to check the key ID)
