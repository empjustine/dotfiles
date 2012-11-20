import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
import XMonad.Util.Run(spawnPipe)
import XMonad.Util.EZConfig(additionalKeys)
import System.IO

main = do
  xmobarProc <- spawnPipe "xmobar .xmobarrc"
  xmonad $ defaultConfig
    { manageHook = manageDocks <+> myManageHook <+> manageHook defaultConfig
    , layoutHook = avoidStruts  $  layoutHook defaultConfig
    , logHook = dynamicLogWithPP xmobarPP
        { ppOutput = hPutStrLn xmobarProc
        , ppTitle = xmobarColor "green" "" . shorten 50
        }
    , modMask = mod4Mask
    } `additionalKeys`
        [ ((mod4Mask .|. shiftMask .|. controlMask, xK_Print), spawn "xterm")
        , ((0, xK_Print), spawn "xterm")
        ]

myManageHook = composeAll
  [ appName =? "push_setup"           --> doFloat -- git-gui push modal dialogs
  , appName =? "__console____o2____d" --> doFloat
  , appName =? "__console____o1____d" --> doFloat
  ]