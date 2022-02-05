#!/bin/bash
# author https://github.com/superiums

slot=''
is_userspace=''
backup_dir="`pwd`/backup"
image_dir=`pwd`
op_island=1

function setting(){
    env
	echo "------------------------------------"
	echo "|            Settings              |"
	echo "------------------------------------"
    echo 
    echo "current slot:$slot"
    echo "current backup dir:$backup_dir"
    echo "current image dir:$image_dir"
    echo "oprate work profile:$op_island"
    echo
    echo "    serialno:     $serialno"
    echo "    product:      $product"
    echo "    slot_suffix:  $slot_suffix"

    read -p "choose your slot (a/b):" slot_
    if [ "$slot_" == 'a' ]; then
        slot="_a"; 
    elif [ "$slot_" == 'b' ]; then
        slot="_b";
    fi

    echo "current backup dir is $backup_dir"
    read -p "enter new backup dir? (Enter to skip)" back_
    if [ -n "$back_" ]; then backup_dir=$back_; fi

    echo "current image dir is $backup_dir"
    read -p "enter new image dir? (Enter to skip)" image_
    if [ -n "$image_" ]; then image_dir=$image_; fi

    echo "do you need to operate work profile created by island?"
    read -p "y/n:" op_
    if [ "$op_" == "y" ]; then op_island=1; else op_island=0;fi
    
}

function do_flash(){
    image="$image_dir/$2"
    echo "---> Flashing $1$slot with $2"
    if [ ! -e $image ]; then
        echo "    File not exist: $image, skipped";
        return
    fi
    echo fastboot flash $1_$slot $image
    if [ "$?" -gt 0 ]; then
        echo "    Failed while flash ${$1}${slot}";
    else
        echo "    OK."
    fi
}

function flash_common(){
    echo "   [flashing common partions]"
    echo "*** warning: continue to Flash will erase all partitions and data"
    read -p "Take your risk. continue anyway? (y/n)" con_
    if [ "$con_" == "y" ]; then
        wait_device bootloader
        common=(vbmeta vbmeta_system boot vendor_boot dtbo)
        for c in ${common[*]};do 
            do_flash $c $c.img
        done
        echo "wiping cache and data"
        echo fastboot -w
    fi
    echo "done in common"
}
function flash_supper(){
    echo "   [flashing supper partions]"
    echo "*** warning: continue to Flash will erase all partitions and data"
    read -p "Take your risk. continue anyway? (y/n)" con_
    if [ "$con_" == "y" ]; then
        wait_device fastbootd
        supper=(vbmeta vbmeta_system boot vendor_boot dtbo)
        for c in ${supper[*]};do 
            do_flash $c $c.img
        done
        echo "wiping cache and data"
        echo fastboot -w
    fi
    echo "done in supper"
}
function do_backup_apks(){
    wait_device adb
        
    # user 0
    echo "---> backing up apks for user 0"
    backdir="$backup_dir/0/"
    if [ ! -d "$backdir" ]; then
        mkdir -p $backdir
    fi
    adb shell pm list packages --user 0 -3 -f |awk '{ORS="\n";sub(/package:/,"adb pull ");sub(/apk=/,"apk '$backdir'");print($0".apk;");print("")}' >$backdir'dolist.sh'
    sh $backdir'dolist.sh' && rm $backdir'dolist.sh'

    # user 10
    if [ "$op_island" gt "0"]; then
        echo "---> backing up apks for user 10"
        backdir="$backup_dir/10/"
        if [ ! -d "$backdir" ]; then
            mkdir -p $backdir
        fi
        adb shell pm list packages --user 10 -3 -f |awk '{ORS="\n";sub(/package:/,"adb pull ");sub(/apk=/,"apk '$backdir'");print($0".apk;");print("")}' >$backdir'dolist.sh'
        sh $backdir'dolist.sh' && rm $backdir'dolist.sh';
    fi
}
function do_backup_dirs(){
    wait_device adb
    echo "---> backing up dirs"
    adb pull /sdcard/Download $backup_dir/
}
function wait_device(){
    if [[ "$1" == "adb" ]]; then
        echo "waiting for device [adb]"
        while true
        do
            local adb_devices=`adb devices |wc -l`
            if [[ $adb_devices -gt "2" ]]; then
                break
            fi
            sleep 1
        done
    fi
    if [[ "$1" == "bootloader" ]]; then
        echo "waiting for device [bootloader]"
        while true
        do
            is_userspace=`fastboot getvar is-userspace`
            read -p "you should see is-userspace:no above. right? (y/n):" inp_
            if [[ $inp_ == "y" ]]; then
                break
            fi
            sleep 1
        done
    fi
    if [[ "$1" == "fastbootd" ]]; then
        echo "waiting for device [fastbootd]"
        while true
        do
            is_userspace=`fastboot getvar is-userspace`
            read -p "you should see is-userspace:no above. right? (y/n):" inp_
            if [[ $inp_ == "y" ]]; then
                break
            fi
            sleep 1
        done
    fi
}
function boot_to_fastbootD(){
    echo "---> rebooting to fastbootD"
    fastboot reboot fastboot
    if [ "$?" -gt 0 ]; then
        echo "! Failed to use fastboot."
    fi
}
function restore_apks(){
    wait_device adb
    echo "---> restoring apks for user 0"
    cd $backup_dir/0
    ls -1 *.apk | xargs -ti -n 1 adb install --user 0 {}
    
    #user 10 for island
    if [[ "$op_island" > 0 ]]; then
        echo "---> restoring apks for user 10"
        cd $backup_dir/10
        ls -1 *.apk | xargs -ti -n 1 adb install --user 10 {}
    fi
}
function restore_dirs(){
    wait_device adb
    echo "---> restoring dirs"
    adb push $backup_dir/Download/* /sdcard/Download/
}
function special_settings(){
    wait_device adb
    echo "---> fix network detection"
    adb shell settings put global captive_portal_http_url http://www.google.cn/generate_204
    adb shell settings put global captive_portal_https_url https://www.google.cn/generate_204

    #disable network active detection
    adb shell settings put global captive_portal_detection_enabled 0
    echo "---> forcing isolate storage"
    #force isolate storage
    adb shell sm set-isolated-storage on
    echo "done"
}
function env(){
    wait_device adb
    serialno=`adb shell getprop ro.boot.serialno`
    slot_suffix=`adb shell getprop ro.boot.slot_suffix`
    product=`adb shell getprop ro.build.product`
    #serialno=`cat moto_edges_getprop.txt | awk -F '[][]' '$2~/ro.boot.serialno/{print $4}'`
    #slot_suffix=`cat moto_edges_getprop.txt | awk -F '[][]' '$2~/ro.boot.slot_suffix/{print $4}'`
    #product=`cat moto_edges_getprop.txt | awk -F '[][]' '$2~/ro.build.product/{print $4}'`
    if [ -z $slot ]; then slot=$slot_suffix; fi
}
function menu(){
	echo "------------------------------------"
	echo "|                                  |"
	echo "|                                  |"
	echo "|     TrinyFlashScript 刷机程式     |"
	echo "|                                  |"
	echo "|                                  |"
	echo "------------------------------------"
	echo "                      by superium   "
    echo 
    echo "current slot:$slot"
    echo "current backup dir:$backup_dir"
    echo "current image dir:$image_dir"
    echo "oprate work profile:$op_island"
    echo
    echo "*** Please start with root permissions, or you may not able to touch your mobile devices."
    echo
    echo "0. settings"
    echo "1. backup apks"
    echo "2. backup dirs"
    echo "3. reboot to bootloader"
    echo "4. reboot to fastbootD"
    echo "5. flash common partitions"
    echo "6. flash supper partitions"
    echo "7. flash all"
    echo "8. restore apks"
    echo "9. restore dirs"
    echo "10. special settings for chinese"
    echo "q. exit"
    echo
    echo "please choose your option："
	read ipt
    if [ -z "${ipt}" -o "${ipt}" == "q" ] ; then
        echo "bye!"
	    exit
    elif [ "${ipt}" == "0" ];then
        setting
    elif [ "${ipt}" == "1" ];then
        do_backup_apks
    elif [ "${ipt}" == "2" ];then
        do_backup_dirs
    elif [ "${ipt}" == "3" ];then
        adb reboot bootloader
        wait_device bootloader
    elif [ "${ipt}" == "4" ];then
        adb reboot fastboot
        if [ "$?" -gt 0 ]; then
            echo "adb not available, tring fastboot"
            boot_to_fastbootD
            wait_device fastbootd
        fi    
    elif [ "${ipt}" == "5" ];then
        flash_common
    elif [ "${ipt}" == "6" ];then
        flash_supper    
    elif [ "${ipt}" == "7" ];then
        adb reboot bootloader
        flash_common
        boot_to_fastbootD
        flash_supper
    elif [ "${ipt}" == "8" ];then
        restore_apks
    elif [ "${ipt}" == "9" ];then
        restore_dirs
    elif [ "${ipt}" == "10" ];then
        special_settings
	fi
    menu
}

menu