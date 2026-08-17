ui_print "============================================"
ui_print " Tensor G2 Battery First Face Safe v12.0"
ui_print "============================================"
ui_print " LITTLE: 1.598 GHz"
ui_print " MID:    1.836 GHz"
ui_print " BIG:    2.188 GHz"
ui_print " CPU6/7: online (Face HAL / Trusty safe)"
ui_print " Governor: sched_pixel"
ui_print " Touch boost: retained"
ui_print " Background uclamp: 35%"
ui_print " System background: stock CPUset and uclamp"
ui_print " Dex2oat uclamp: 60%"
ui_print " Display refresh rate: unchanged"
ui_print " Config: $MODPATH/config.txt"
ui_print " Log:    $MODPATH/opt.log"
ui_print "============================================"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/config.txt" 0 0 0644
