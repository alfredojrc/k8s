# Snapshot Management Documentation

## Overview

The snapshot management functionality in the k8s-manager.sh script provides a comprehensive set of tools for managing VMware Fusion snapshots across your Kubernetes cluster VMs. This documentation covers how to use these features to create, list, roll back to, and delete snapshots.

## Table of Contents

1. [Accessing Snapshot Management](#accessing-snapshot-management)
2. [Snapshot Submenu Options](#snapshot-submenu-options)
3. [Creating Snapshots for All VMs](#creating-snapshots-for-all-vms)
4. [Listing Snapshots](#listing-snapshots)
5. [Rolling Back VMs to a Snapshot](#rolling-back-vms-to-a-snapshot)
6. [Deleting Snapshots](#deleting-snapshots)
7. [Managing Snapshots for a Specific VM](#managing-snapshots-for-a-specific-vm)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)

## Accessing Snapshot Management

From the main menu of k8s-manager.sh, select option 4: "Manage snapshots (submenu)". This will open the dedicated snapshot management interface.

```
Kubernetes Cluster Management Menu
1) Deploy Kubernetes Cluster (Full Workflow)
2) Create all VMs and basic configuration
3) Check VM status and network configuration
4) Manage snapshots (submenu)
5) Delete all VMs
6) Deploy Kubernetes on existing VMs
7) Power on all VMs
8) Shutdown all VMs
9) Update VM IP addresses
0) Exit

Enter your choice:
```

## Snapshot Submenu Options

The snapshot management submenu offers the following options:

```
Snapshot Management Submenu
1) Create snapshot for all VMs
2) List snapshots for all VMs
3) Rollback all VMs to a specific snapshot
4) Delete snapshots from all VMs
5) Delete a specific snapshot from a specific VM
6) Manage snapshots for a specific VM
0) Return to main menu

Enter your choice:
```

## Creating Snapshots for All VMs

This option allows you to create a snapshot with the same name across all VMs in your Kubernetes cluster. This is particularly useful before making significant changes to your infrastructure.

### How to Use:

1. Select option 1 from the snapshot submenu
2. Enter a descriptive name for the snapshot (avoid using '/' characters)
3. Optionally, enter a description for the snapshot
4. The system will create snapshots for all VMs in parallel

### Features:

- Automatically adds a timestamp to the snapshot name for uniqueness
- Creates snapshots in parallel for faster processing
- Works with both running and powered-off VMs
- Provides status updates during the snapshot creation process

### Example:

```
Enter a descriptive name for this snapshot (avoid using '/' characters):
pre_upgrade

Enter a description for this snapshot (optional, hit Enter to skip):
Before upgrading Kubernetes to v1.27

Creating snapshots in parallel for all VMs...
Starting snapshot creation for haproxy1...
VM haproxy1 is running. Taking snapshot...
Starting snapshot creation for haproxy2...
VM haproxy2 is running. Taking snapshot...
...

All snapshots have been created.
Snapshot Name: pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27
```

## Listing Snapshots

This option displays all available snapshots across all VMs in your cluster.

### How to Use:

1. Select option 2 from the snapshot submenu
2. The system will list all snapshots for each VM

### Example Output:

```
Snapshots for haproxy1:
- initial_setup_20230410_092154
- pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27

Snapshots for haproxy2:
- initial_setup_20230410_092154
- pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27

Snapshots for k8s-master1:
...
```

## Rolling Back VMs to a Snapshot

This powerful feature allows you to roll back all VMs to a specific snapshot point. The system will revert each VM that has the selected snapshot name.

### How to Use:

1. Select option 3 from the snapshot submenu
2. The system will collect and display snapshot information from all VMs
3. Select a snapshot to roll back to
4. Confirm the rollback operation

### Features:

- Safely powers off VMs before rollback if they're running
- Only rolls back VMs that have the selected snapshot
- Restarts VMs that were running before the rollback
- Provides a detailed summary of successful, skipped, and failed rollbacks

### Example:

```
Available snapshots across all VMs:
1) initial_setup_20230410_092154
2) pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27

Select a snapshot to rollback all VMs to (1-2):
2

Warning: This will attempt to rollback ALL VMs to snapshot 'pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27'.
Each VM will only be rolled back if it has this snapshot.
All changes since the snapshot will be lost.
Are you sure you want to continue? (y/n)
y

Rolling back VM haproxy1 to snapshot 'pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27'...
Successfully rolled back VM haproxy1 to snapshot 'pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27'
...

Rollback Summary:
Snapshot: pre_upgrade_20230415_143022 - Before upgrading Kubernetes to v1.27

Successfully rolled back:
- haproxy1
- haproxy2
- k8s-master1
- k8s-master2
- k8s-master3
- k8s-worker1
- k8s-worker2
```

## Deleting Snapshots

This option allows you to delete all snapshots from all VMs. It's useful for cleaning up disk space when snapshots are no longer needed.

### How to Use:

1. Select option 4 from the snapshot submenu
2. Confirm the deletion operation

### Features:

- Provides warnings about VMs that need to be stopped for snapshot deletion
- Shows progress for each VM
- Reports success or failure for each snapshot deletion

## Deleting a Specific Snapshot from a Specific VM

This option provides more granular control by allowing you to delete a specific snapshot from a single VM.

### How to Use:

1. Select option 5 from the snapshot submenu
2. Select the VM from the list
3. Select the snapshot to delete
4. Confirm the deletion

### Features:

- Offers the option to power off the VM if needed for snapshot deletion
- Provides detailed error information if deletion fails

## Managing Snapshots for a Specific VM

This option opens a VM-specific snapshot management submenu for more focused operations.

### How to Use:

1. Select option 6 from the snapshot submenu
2. Select the VM you want to manage
3. Choose from the VM-specific snapshot options:
   - Create snapshot
   - List snapshots
   - Rollback to snapshot
   - Delete snapshot

### Features:

- Targeted snapshot management for a single VM
- Full control over individual VM snapshot lifecycle

## Best Practices

1. **Naming Conventions**: Use descriptive names for snapshots that indicate their purpose, for example:
   - `pre_upgrade_kubernetes` - Before upgrading Kubernetes
   - `after_network_config` - After configuring networking
   - `stable_deployment` - Known stable state

2. **Snapshot Timing**:
   - Create snapshots before making significant changes to your infrastructure
   - Create snapshots when your cluster is in a known good state
   - Consider creating snapshots before and after major updates

3. **Snapshot Cleanup**:
   - Regularly delete old snapshots that are no longer needed
   - Keep the snapshot chain relatively short for better performance
   - Clean up snapshots after confirming changes work as expected

4. **VM State**:
   - For the most consistent snapshots, consider shutting down VMs before creating snapshots
   - Be aware that snapshots of running VMs capture memory state, which can use significant disk space

## Troubleshooting

### Common Issues and Solutions

1. **Failed Snapshot Creation**
   - Ensure the VM has sufficient disk space
   - Check VMware Fusion version compatibility
   - Try creating the snapshot with the VM powered off

2. **Failed Snapshot Deletion**
   - Some snapshots can only be deleted when the VM is powered off
   - Try using the VMware Fusion UI to delete the snapshot
   - Check if the snapshot is part of a chain that has dependent snapshots

3. **Failed Rollback**
   - Ensure the VM is powered off for reliable rollback
   - Check for locked files or other processes accessing the VM
   - Verify the snapshot exists and is valid

4. **Performance Issues After Snapshot**
   - Too many snapshots can impact performance
   - Delete and consolidate old snapshots
   - Consider fresh VM creation if performance remains poor

### Manual Snapshot Management

If the script's snapshot management functionality doesn't resolve your issue, you can use VMware Fusion's UI or command-line tools directly:

1. **Using VMware Fusion UI**:
   - Open VMware Fusion
   - Select the VM from the Virtual Machine Library
   - Click on 'Virtual Machine' in the menu bar
   - Select 'Snapshots' (or press Shift+Command+S)
   - Use the snapshot interface to create, revert to, or delete snapshots

2. **Using Terminal Commands**:
   - List available VMs: `vmrun -T fusion list`
   - List snapshots: `vmrun -T fusion listSnapshots "/path/to/vm.vmx"`
   - Create snapshot: `vmrun -T fusion snapshot "/path/to/vm.vmx" "snapshot_name"`
   - Delete snapshot: `vmrun -T fusion deleteSnapshot "/path/to/vm.vmx" "snapshot_name"`
   - Revert to snapshot: `vmrun -T fusion revertToSnapshot "/path/to/vm.vmx" "snapshot_name"` 