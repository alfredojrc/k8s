# Snapshot Management in K8s Cluster Manager

This document provides detailed information about the snapshot management capabilities of the K8s Cluster Manager script.

## Table of Contents

1. [Introduction to Snapshots](#introduction-to-snapshots)
2. [Accessing Snapshot Management](#accessing-snapshot-management)
3. [Snapshot Display Table](#snapshot-display-table)
4. [Creating Snapshots](#creating-snapshots)
5. [Listing Snapshots](#listing-snapshots)
6. [Rolling Back to Snapshots](#rolling-back-to-snapshots)
7. [Deleting Snapshots](#deleting-snapshots)
8. [VMware Fusion Integration](#vmware-fusion-integration)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## Introduction to Snapshots

VMware Fusion snapshots capture the complete state of a virtual machine at a specific point in time. A snapshot includes:

- **Memory State**: The contents of the virtual machine memory
- **Settings State**: The virtual machine settings
- **Disk State**: The state of all virtual disks

Snapshots are particularly useful for:
- Preserving a known good state before making changes
- Testing configurations without committing to them
- Creating recovery points for critical operations
- Rolling back after failed updates or installations

## Accessing Snapshot Management

Access the snapshot management functions by following these steps:

1. Launch the K8s Cluster Manager script:
   ```
   ./k8s-manager.sh
   ```

2. From the main menu, select option 4 "Manage snapshots (submenu)"

3. This will open the Snapshot Management Submenu:
   ```
   =========================================================
   Snapshot Management Submenu
   =========================================================
   1) Create snapshot for all VMs
   2) List snapshots for all VMs
   3) Rollback to a specific snapshot
   4) Delete a snapshot from all VMs
   5) Delete a specific snapshot from a specific VM
   6) Show manual snapshot deletion instructions
   0) Return to main menu
   ```

## Snapshot Display Table

The snapshot table (option 2) provides a visual representation of all VMs and their snapshots:

```
=== VM Snapshot Table ===
+-----------------+-------------+-------------+
| VM Name         | Snapshot1   | Snapshot2   |
+-----------------+-------------+-------------+
| haproxy1        | ✓           | ✖           |
| haproxy2        | ✖           | ✖           |
| k8s-master1     | ✓           | ✖           |
| k8s-master2     | ✓           | ✓           |
| k8s-master3     | ✖           | ✖           |
| k8s-worker1     | ✓           | ✖           |
| k8s-worker2     | ✓           | ✖           |
+-----------------+-------------+-------------+
```

### Table Features

- **Color-Coded VM Names**:
  - **Green**: Running VMs
  - **Blue**: Powered-off VMs

- **Snapshot Status Indicators**:
  - **✓** (Green): Snapshot exists for this VM
  - **✖** (Red): Snapshot does not exist for this VM
  - **!** (Red): Error getting snapshot data

- **Summary Information**:
  - Total VMs and their power status
  - Total unique snapshots across all VMs
  - List of VMs with no snapshots

## Creating Snapshots

Option 1 in the snapshot submenu creates a snapshot across all VMs simultaneously:

### Process

1. Select option 1 "Create snapshot for all VMs"
2. Enter a name for the snapshot when prompted
   ```
   Enter a name for the snapshot (avoid using '/' characters):
   ```
3. The script creates snapshots in parallel for faster processing
4. A status message is displayed for each VM during creation

### Notes

- Do not use forward slashes (`/`) in snapshot names as they are used as path separators in VMware Fusion
- Choose descriptive names that indicate the state or purpose of the snapshot
- Each snapshot requires additional disk space proportional to changes made after the snapshot

## Listing Snapshots

Option 2 displays a comprehensive table showing all VMs and their snapshots:

### Process

1. Select option 2 "List snapshots for all VMs"
2. The script scans all VMs for their snapshots
3. A table is displayed showing all VMs and which snapshots they have
4. Summary information is shown below the table

### Reading the Table

- Each row represents a VM in your cluster
- Each column (after the VM name) represents a unique snapshot
- Intersections show whether a particular VM has a specific snapshot
- The color of the VM name indicates its power state

## Rolling Back to Snapshots

Option 3 allows you to restore a VM to a previous snapshot state:

### Process

1. Select option 3 "Rollback to a specific snapshot"
2. Choose a VM from the list:
   ```
   Available VMs:
   1) haproxy1
   2) haproxy2
   3) k8s-master1
   ...
   Select a VM to view snapshots (1-7):
   ```
3. Select a snapshot to roll back to:
   ```
   Snapshots for k8s-master1:
   1) initial_setup
   2) pre_upgrade
   Select a snapshot to rollback to (1-2):
   ```
4. Confirm the rollback operation
5. The script handles powering off the VM if needed and reverting to the snapshot

### Important Notes

- **WARNING**: Rolling back to a snapshot discards all changes made since the snapshot was taken
- If the VM is running, it will be powered off before the rollback
- After rollback, the VM will be returned to its previous power state
- A rollback operation cannot be undone

## Deleting Snapshots

The script provides two different options for deleting snapshots:

### Option 4: Delete a Snapshot from All VMs

This operation removes a specific snapshot from all VMs that have it:

1. Select option 4 "Delete a snapshot from all VMs"
2. Choose from the list of unique snapshots:
   ```
   Available snapshots:
   1) initial_setup
   2) pre_upgrade
   Select a snapshot to delete (1-2):
   ```
3. Confirm the deletion
4. The script will delete the snapshot from every VM that has it
5. A summary is displayed showing which deletions were successful

### Option 5: Delete a Specific Snapshot from a Specific VM

This operation targets a single snapshot on a single VM:

1. Select option 5 "Delete a specific snapshot from a specific VM"
2. Choose a VM from the list
3. Choose a snapshot from that VM's available snapshots
4. If the VM is running, you'll be asked if you want to power it off first
5. Confirm the deletion
6. Status messages are displayed during the process

### Notes on Snapshot Deletion

- Snapshot deletion might take time, especially for large VMs
- VMware Fusion consolidates disks after snapshot deletion
- Some snapshots can only be deleted when the VM is powered off
- The script will offer to restart a VM if it was powered off for deletion

## VMware Fusion Integration

The snapshot management leverages VMware Fusion's `vmrun` command-line interface:

### Key Commands Used

- **Create snapshot**: `vmrun -T fusion snapshot "/path/to/vm.vmx" "snapshot_name"`
- **List snapshots**: `vmrun -T fusion listSnapshots "/path/to/vm.vmx"`
- **Revert to snapshot**: `vmrun -T fusion revertToSnapshot "/path/to/vm.vmx" "snapshot_name"`
- **Delete snapshot**: `vmrun -T fusion deleteSnapshot "/path/to/vm.vmx" "snapshot_name"`

### Manual Snapshot Management

Option 6 "Show manual snapshot deletion instructions" provides guidance for managing snapshots directly through VMware Fusion:

1. **Using VMware Fusion UI**:
   - Select the VM in the Virtual Machine Library
   - Click Virtual Machine > Snapshots
   - Use the Snapshots window to manage snapshots

2. **Using Terminal Commands**:
   - Examples of direct `vmrun` commands are shown
   - Includes instructions specific to your VM cluster directory

## Best Practices

For optimal snapshot management:

1. **Name snapshots clearly**:
   - Use descriptive names that indicate the state or purpose
   - Include dates or version numbers for easier tracking
   - Avoid special characters, especially forward slashes (`/`)

2. **Use snapshots strategically**:
   - Create snapshots before major changes or updates
   - Create snapshots before configuration changes
   - Don't overuse snapshots as they consume disk space

3. **Manage snapshot lifecycle**:
   - Delete snapshots that are no longer needed
   - Don't keep snapshots indefinitely
   - Consider creating a backup instead of long-term snapshots

4. **Performance considerations**:
   - Having multiple snapshots can impact VM performance
   - Very large VMs take longer to snapshot
   - Close other applications while creating snapshots for better performance

## Troubleshooting

Common snapshot issues and their solutions:

### Creation Issues

- **Error**: "Failed to create snapshot"
  - **Solution**: Ensure VMware Fusion has write permissions to the VM directory
  - **Solution**: Verify enough disk space is available
  - **Solution**: Try closing other applications to free up resources

### Deletion Issues

- **Error**: "Failed to delete snapshot"
  - **Solution**: Power off the VM first, as some snapshots require this
  - **Solution**: Check if the snapshot is in use by another operation
  - **Solution**: Try deleting through the VMware Fusion UI as a workaround

### Rollback Issues

- **Error**: "Failed to revert to snapshot"
  - **Solution**: Ensure the VM is not locked by another process
  - **Solution**: Verify the snapshot still exists
  - **Solution**: Power off the VM manually first

### Display Issues

- **Issue**: Table doesn't show all snapshots
  - **Solution**: Run the list command again
  - **Solution**: Verify snapshot names don't contain special characters

- **Issue**: Color coding not visible
  - **Solution**: Ensure your terminal supports ANSI color codes 