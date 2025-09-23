{ ... }:

{
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.moeleak = {
    isNormalUser = true;
    description = "moeleak";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };
}
