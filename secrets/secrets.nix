{ config, lib, ... }:

let
  # Function to safely read a secret file, returning an empty set if it doesn't exist
  # This prevents evaluation errors during initial setup or on machines without the secrets
  readSecret = file: 
    if builtins.pathExists file 
    then builtins.fromJSON (builtins.readFile file)
    else {};

  onyxSecrets = readSecret ./onyx.secret;
in
{
  options.mySecrets = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Decrypted secrets loaded from JSON files";
  };

  config.mySecrets = {
    onyx = onyxSecrets;
  };
}

