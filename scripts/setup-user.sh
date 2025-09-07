#!/bin/bash

# Script to create user 'tianzhic' with email and docker group
# Usage: sudo ./setup-user.sh

set -e  # Exit on any error

USER_NAME="tianzhic"
USER_EMAIL="tianzhic.dev@gmail.com"
GROUP_NAME="docker"

echo "Setting up user: $USER_NAME"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Create docker group if it doesn't exist
if ! getent group $GROUP_NAME > /dev/null 2>&1; then
    echo "Creating group: $GROUP_NAME"
    groupadd $GROUP_NAME
    echo "Group $GROUP_NAME created successfully"
else
    echo "Group $GROUP_NAME already exists"
fi

# Check if user already exists
if id "$USER_NAME" &>/dev/null; then
    echo "User $USER_NAME already exists"
    # Add user to docker group if not already a member
    if ! groups $USER_NAME | grep -q "\b$GROUP_NAME\b"; then
        echo "Adding $USER_NAME to $GROUP_NAME group"
        usermod -a -G $GROUP_NAME $USER_NAME
        echo "User $USER_NAME added to $GROUP_NAME group"
    else
        echo "User $USER_NAME is already in $GROUP_NAME group"
    fi
    # Add user to sudo group if not already a member
    if ! groups $USER_NAME | grep -q "\bsudo\b"; then
        echo "Adding $USER_NAME to sudo group"
        usermod -a -G sudo $USER_NAME
        echo "User $USER_NAME added to sudo group"
    else
        echo "User $USER_NAME is already in sudo group"
    fi
else
    echo "Creating user: $USER_NAME"
    # Create user with home directory and add to docker and sudo groups
    useradd -m -s /bin/bash -G $GROUP_NAME,sudo $USER_NAME
    echo "User $USER_NAME created successfully"
fi

# Set up user info (email in GECOS field)
echo "Setting user information"
usermod -c "$USER_EMAIL" $USER_NAME

# Add user to sudoers
echo "Adding $USER_NAME to sudoers"
usermod -a -G sudo $USER_NAME
echo "User $USER_NAME added to sudo group"

# Set up SSH directory with proper permissions
USER_HOME="/home/$USER_NAME"
SSH_DIR="$USER_HOME/.ssh"

if [ ! -d "$SSH_DIR" ]; then
    echo "Creating SSH directory"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown $USER_NAME:$USER_NAME "$SSH_DIR"
    echo "SSH directory created at $SSH_DIR"
fi

# Create authorized_keys file if it doesn't exist
AUTH_KEYS="$SSH_DIR/authorized_keys"
if [ ! -f "$AUTH_KEYS" ]; then
    touch "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    chown $USER_NAME:$USER_NAME "$AUTH_KEYS"
    echo "Created authorized_keys file at $AUTH_KEYS"
fi

# Display user info
echo ""
echo "User setup completed successfully!"
echo "Username: $USER_NAME"
echo "Email: $USER_EMAIL"
echo "Groups: $(groups $USER_NAME)"
echo "Home directory: $USER_HOME"
echo ""
echo "Next steps:"
echo "1. Set password for $USER_NAME: sudo passwd $USER_NAME"
echo "2. Add SSH public key to: $AUTH_KEYS"
echo "3. Test SSH access"
echo "4. Verify docker access: sudo -u $USER_NAME docker --version"
echo "5. Test sudo access: su - $USER_NAME -c 'sudo whoami'"