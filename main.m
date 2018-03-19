/*
 For an A to Z discussion, please visit http://bbs.iosre.com/t/write-a-simple-universal-memory-editor-game-trainer-on-osx-ios-from-scratch/115
 
 mach_vm functions reference: http://www.opensource.apple.com/source/xnu/xnu-1456.1.26/osfmk/vm/vm_user.c
 
 OSX: clang -framework Foundation -o HippocampHairSalon_OSX main.m
 
 iOS: clang -isysroot `xcrun --sdk iphoneos --show-sdk-path` -arch armv7 -arch arm64 -framework Foundation -o HippocampHairSalon_iOS main.m
 Then: ldid -Sent.xml HippocampHairSalon_iOS
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR // Imports from /usr/lib/system/libsystem_kernel.dylib
extern kern_return_t
mach_vm_read(
             vm_map_t        map,
             mach_vm_address_t    addr,
             mach_vm_size_t        size,
             pointer_t        *data,
             mach_msg_type_number_t    *data_size);

extern kern_return_t
mach_vm_write(
              vm_map_t            map,
              mach_vm_address_t        address,
              pointer_t            data,
              __unused mach_msg_type_number_t    size);

extern kern_return_t
mach_vm_region(
               vm_map_t         map,
               mach_vm_offset_t    *address,
               mach_vm_size_t        *size,
               vm_region_flavor_t     flavor,
               vm_region_info_t     info,
               mach_msg_type_number_t    *count,
               mach_port_t        *object_name);

extern kern_return_t mach_vm_protect(vm_map_t, mach_vm_address_t, mach_vm_size_t, boolean_t, vm_prot_t);

#else
#include <mach/mach_vm.h>
#endif

static NSArray *AllProcesses(void) // Taken from http://forrst.com/posts/UIDevice_Category_For_Processes-h1H
{
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    size_t size;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    struct kinfo_proc *process = NULL;
    struct kinfo_proc *newprocess = NULL;
    do
    {
        size += size / 10;
        newprocess = realloc(process, size);
        if (!newprocess)
        {
            if (process)
            {
                free(process);
            }
            return nil;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
    }
    while (st == -1 && errno == ENOMEM);
    if (st == 0)
    {
        if (size % sizeof(struct kinfo_proc) == 0)
        {
            int nprocess = size / sizeof(struct kinfo_proc);
            if (nprocess)
            {
                NSMutableArray * array = [[NSMutableArray alloc] init];
                for (int i = nprocess - 1; i >= 0; i--)
                {
                    NSString * processID = [[NSString alloc] initWithFormat:@"%d", process[i].kp_proc.p_pid];
                    NSString * processName = [[NSString alloc] initWithFormat:@"%s", process[i].kp_proc.p_comm];
                    NSDictionary * dictionary = [[NSDictionary alloc] initWithObjects:[NSArray arrayWithObjects:processID, processName, nil] forKeys:[NSArray arrayWithObjects:@"ProcessID", @"ProcessName", nil]];
                    [array addObject:dictionary];
                }
                free(process);
                return array;
            }
        }
    }
    return nil;
}

int main(int argc, char *argv[])
{
    // Output all Process IDs and names
    printf("[PID] ProcessName\n");
    for (NSDictionary *process in AllProcesses())
    {
        printf("[%s] %s\n", [(NSString *)[process objectForKey:@"ProcessID"] UTF8String], [(NSString *)[process objectForKey:@"ProcessName"] UTF8String]);
    }
    
    // Prompt
    printf("Enter target PID: ");
    int pid = 0;
    scanf("%d", &pid);
    
    // Get task of specified PID
    kern_return_t kret;
    mach_port_t task; // type vm_map_t = mach_port_t in mach_types.defs
    if ((kret = task_for_pid(mach_task_self(), pid, &task)) != KERN_SUCCESS)
    {
        printf("task_for_pid() failed, error %d: %s. Forgot to run as root?\n", kret, mach_error_string(kret));
        exit(1);
    }
    
    NSMutableArray *substringArray = [[NSMutableArray alloc] initWithCapacity:666]; // Store searched memory addresses for review, saving another iteration of mach_vm_region
    NSMutableArray *protectionArray = [[NSMutableArray alloc] initWithCapacity:666]; // Store searched memory region protection for review, saving another iteration of mach_vm_region
    
Search:
    // Prompt
    printf("Enter the value to search: ");
    int oldValue = 0; // change type: unsigned int, long, unsigned long, etc. Should be customizable!
    scanf("%d", &oldValue);
    
    // Output all searched results
    mach_vm_offset_t address = 0;
    mach_vm_size_t size;
    mach_port_t object_name;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    int occurranceCount = 0;
    [substringArray removeAllObjects];
    [protectionArray removeAllObjects];
    while (mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS)
    {
        pointer_t buffer;
        mach_msg_type_number_t bufferSize = size;
        vm_prot_t protection = info.protection;
        if ((kret = mach_vm_read(task, (mach_vm_address_t)address, size, &buffer, &bufferSize)) == KERN_SUCCESS)
        {
            void *substring = NULL;
            if ((substring = memmem((const void *)buffer, bufferSize, &oldValue, sizeof(oldValue))) != NULL)
            {
                occurranceCount++;
                
                long realAddress = (long)substring - (long)buffer + (long)address;
                printf("Search result %2d: %d at 0x%0lx (%s)\n", occurranceCount, oldValue, realAddress, (protection & VM_PROT_WRITE) != 0 ? "writable" : "non-writable");
                [substringArray addObject:[NSNumber numberWithLong:realAddress]];
                [protectionArray addObject:[NSString stringWithUTF8String:(protection & VM_PROT_WRITE) != 0 ? "writable" : "non-writable"]];
            }
        }
        // else printf("mac_vm_read fails, error %d: %s\n", kret, mach_error_string(kret));
        address += size;
    }
    
NextAction:
    // Prompt
    printf("1. Modify search results;\n2. Review search results;\n3. Search something else.\nPlease choose your next action: ");
    int nextAction;
    scanf("%d", &nextAction);
    
    // Modify searched results or review them
    switch (nextAction)
    {
        case 1:
        {
            // Prompt
            while (getchar() != '\n') continue; // clear buffer
            printf("Enter the address of modification: ");
            mach_vm_address_t modAddress;
            scanf("0x%llx", &modAddress);
            
            if ([substringArray indexOfObject:[NSNumber numberWithLongLong:modAddress]] == NSNotFound)
            {
                printf("This address is not in search results, hence invalid. Please re-enter.\n");
                goto NextAction;
            }
            
            while (getchar() != '\n') continue; // clear buffer
            printf("Enter the new value: ");
            int newValue; // change type: unsigned int, long, unsigned long, etc. Should be customizable!
            scanf("%d", &newValue);
            //Changes for iOS9 ASLR
            //get original memory protection
            mach_vm_size_t size = 0;
            mach_port_t object_name = 0;
            vm_region_basic_info_data_64_t info = {0};
            mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
            /* mach_vm_region will return the address of the map into the address argument so we need to make a copy */
            mach_vm_address_t dummyadr = modAddress;
            if ( (kret = mach_vm_region(task, &dummyadr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name)) )
            {
                printf("mach_vm_region failed with error %d", kret);
                exit(1);
            }
            
            //change protections, write, and restore original protection
            task_suspend(task);
            if ( (kret = mach_vm_protect(task, modAddress, sizeof(newValue), FALSE, VM_PROT_WRITE | VM_PROT_READ | VM_PROT_COPY)) )
            {
                printf("mach_vm_protect failed with error %d.", kret);
                exit(1);
            }
            
            if ( (kret = mach_vm_write(task, modAddress, (pointer_t)&newValue, sizeof(newValue))) )
            {
                printf("mach_vm_write failed at 0x%llx with error %d.", modAddress, kret);
                exit(1);
            }
            // restore original protection
            if ( (kret = mach_vm_protect(task, modAddress, sizeof(newValue), FALSE, info.protection)) )
            {
                printf("mach_vm_protect failed with error %d.", kret);
                exit(1);
            }
            task_resume(task);
            
            goto NextAction;
        }
        case 2:
        {
            for (int i = 0; i < [substringArray count]; i++)
            {
                NSNumber *substringNumber = [substringArray objectAtIndex:i];
                pointer_t buffer;
                size = sizeof(int); // because oldValue and newValue are int
                mach_msg_type_number_t bufferSize = size;
                
                long substring = [substringNumber longValue];
                if ((kret = mach_vm_read(task, (mach_vm_address_t)substring, size, &buffer, &bufferSize)) == KERN_SUCCESS)
                {
                    printf("Search result %2d: %ld at 0x%0llx (%s)\n", i + 1, *(long *)buffer, (mach_vm_address_t)substring, [[protectionArray objectAtIndex:i] UTF8String]);
                }
                else printf("mach_vm_read failed at 0x%0llx, error %d: %s\n", (mach_vm_address_t)substring, kret, mach_error_string(kret));
            }
            goto NextAction;
        }
        case 3:
        {
            goto Search;
        }
        default:
        {
            printf("Unknown action. Please re-enter.\n");
            goto NextAction;
        }
    }
    return 0;
}

