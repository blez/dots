import qualified Data.Map as M
import Data.Monoid
import Graphics.X11.ExtraTypes.XF86
import System.Exit
import System.IO (hPutStrLn)
import XMonad
import XMonad.Actions.CycleWS
import XMonad.Hooks.DynamicLog (PP (..), dynamicLogWithPP, shorten, wrap, xmobarColor, xmobarPP)
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.FadeWindows
import XMonad.Hooks.ManageDocks (ToggleStruts (..), avoidStruts, docksEventHook, manageDocks)
import XMonad.Hooks.ManageHelpers (doFullFloat, isFullscreen)

import XMonad.Layout.GridVariants (Grid (Grid))
import XMonad.Layout.LayoutModifier
import XMonad.Layout.LimitWindows (decreaseLimit, increaseLimit, limitWindows)
import XMonad.Layout.MultiToggle (EOT (EOT), mkToggle, single, (??))
import qualified XMonad.Layout.MultiToggle as MT (Toggle (..))
import XMonad.Layout.MultiToggle.Instances (StdTransformers (MIRROR, NBFULL, NOBORDERS))
import XMonad.Layout.NoBorders
import XMonad.Layout.MultiColumns
import XMonad.Layout.Renamed
import XMonad.Layout.ResizableTile
import XMonad.Layout.ShowWName
import XMonad.Layout.Simplest
import XMonad.Layout.SimplestFloat
import XMonad.Layout.Spacing
import XMonad.Layout.Spiral
import XMonad.Layout.SubLayouts
import XMonad.Layout.Tabbed
import qualified XMonad.Layout.ToggleLayouts as T (ToggleLayout (Toggle), toggleLayouts)
import XMonad.Layout.WindowArranger (WindowArrangerMsg (..), windowArrange)
import XMonad.Layout.WindowNavigation

import qualified XMonad.StackSet as W
import XMonad.Util.EZConfig (additionalKeys)
import XMonad.Util.Run
import XMonad.Util.SpawnOnce

myFont :: String
myFont = "xft:JetBrains Mono Nerd Font:regular:size=14:antialias=true:hinting=true"

myTerminal :: [Char]
myTerminal = "alacritty"

myFocusFollowsMouse :: Bool
myFocusFollowsMouse = True

myClickJustFocuses :: Bool
myClickJustFocuses = False

myBorderWidth :: Dimension
myBorderWidth = 3

myModMask :: KeyMask
myModMask = mod4Mask

myWorkspaces :: [String]
myWorkspaces =
  [ "<icon=Emacs.xpm/>",
    "<icon=Terminal.xpm/>",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "<icon=Chat.xpm/>"
  ]
    ++ (map snd myExtraWorkspaces)

myExtraWorkspaces = [(xK_0, "<icon=Chrome.xpm/>")]

myNormalBorderColor = "#ffffff"

-- myFocusedBorderColor = "#ff0000"
myFocusedBorderColor = "#33a38f"

myAdditionalKeys =
  [ ((myModMask, key), (windows $ W.greedyView ws))
    | (key, ws) <- myExtraWorkspaces
  ]
    ++ [ ((myModMask .|. shiftMask, key), (windows $ W.shift ws))
         | (key, ws) <- myExtraWorkspaces
       ]

myKeys conf@(XConfig {XMonad.modMask = modm}) =
  M.fromList $
    -- launch a terminal
    [ ((modm .|. shiftMask, xK_Return), spawn $ XMonad.terminal conf),
      -- launch dmenu
      ((modm, xK_x), spawn "~/.config/rofi/run.sh"),
      ((modm, xK_p), spawn "rofi -show drun"),
      -- launch gmrun
      ((modm .|. shiftMask, xK_p), spawn "gmrun"),
      -- lock
      ((modm .|. shiftMask, xK_l), spawn "i3lock -i ~/wallpapers/lock.png"),
      -- sleep
      ((modm .|. shiftMask, xK_s), spawn "i3lock -i ~/wallpapers/lock.png && systemctl suspend"),
      -- keyboard layout
      ((modm, xK_space), spawn "~/scripts/kb-switch.sh"),
      -- close focused window
      ((modm, xK_q), kill),
      -- Rotate through the available layout algorithms
      ((modm, xK_Tab), sendMessage NextLayout),
      --  Reset the layouts on the current workspace to default
      ((modm .|. shiftMask, xK_space), setLayout $ XMonad.layoutHook conf),
      -- Resize viewed windows to the correct size
      ((modm, xK_n), refresh),
      -- Move focus to the next window
      -- , ((modm,               xK_Tab   ), windows W.focusDown)

      -- Move focus to the next window
      ((modm, xK_j), windows W.focusDown),
      -- Move focus to the previous window
      ((modm, xK_k), windows W.focusUp),
      -- Move focus to the master window
      ((modm, xK_m), windows W.focusMaster),
      -- Swap the focused window and the master window
      ((modm, xK_Return), windows W.swapMaster),
      -- Swap the focused window with the next window
      ((modm .|. shiftMask, xK_j), windows W.swapDown),
      -- Swap the focused window with the previous window
      ((modm .|. shiftMask, xK_k), windows W.swapUp),
      -- Shrink the master area
      ((modm, xK_h), sendMessage Shrink),
      -- Expand the master area
      ((modm, xK_l), sendMessage Expand),
      -- Push window back into tiling
      ((modm, xK_t), withFocused $ windows . W.sink),
      -- Increment the number of windows in the master area
      ((modm, xK_comma), sendMessage (IncMasterN 1)),
      -- Deincrement the number of windows in the master area
      ((modm .|. shiftMask, xK_period), sendMessage (IncMasterN (-1))),
      -- Toggle the status bar gap
      -- Use this binding with avoidStruts from Hooks.ManageDocks.
      -- See also the statusBar function from Hooks.DynamicLog.
      --
      -- , ((modm              , xK_b     ), sendMessage ToggleStruts)

      -- Audio controll using Fn + F1,F2,F3
      ((0, xF86XK_AudioMute), spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle"),
      ((0, xF86XK_AudioLowerVolume), spawn "pactl set-sink-volume @DEFAULT_SINK@ -2%"),
      ((0, xF86XK_AudioRaiseVolume), spawn "pactl set-sink-volume @DEFAULT_SINK@ +2%"),
      ((modm .|. shiftMask, xK_minus), spawn "pactl set-sink-mute @DEFAULT_SINK@ toggle"),
      ((modm, xK_minus), spawn "pactl set-sink-volume @DEFAULT_SINK@ -2%"),
      ((modm, xK_equal), spawn "pactl set-sink-volume @DEFAULT_SINK@ +2%"),
      -- Playerctl
      ((modm .|. shiftMask, xK_i), spawn "~/scripts/playerctl.sh play"),
      ((modm .|. shiftMask, xK_u), spawn "~/scripts/playerctl.sh prev"),
      ((modm .|. shiftMask, xK_o), spawn "~/scripts/playerctl.sh next"),
      ((0, xF86XK_AudioPause), spawn "~/scripts/playerctl.sh play"),
      ((0, xF86XK_AudioPlay), spawn "~/scripts/playerctl.sh play"),
      ((0, xF86XK_AudioNext), spawn "~/scripts/playerctl.sh next"),
      ((0, xF86XK_AudioPrev), spawn "~/scripts/playerctl.sh prev"),
      -- Bluetooth devices
      -- requires `sudo apt-get install bluez-tools`
      ((modm, xK_b), spawn "notify-send -t 3000 --app-name 'bluetooth' \"$(~/scripts/blue-cmd.sh pause)\""),
      ((modm .|. shiftMask, xK_b), spawn "notify-send -t 3000 --app-name 'bluetooth' \"$(~/scripts/blue-cmd.sh play)\""),

      --take a screenshot of entire display
      ((0, xK_Print), spawn "flameshot gui"),
      ((modm, xK_Print), spawn "flameshot full -p ~/Pictures/"),
      -- Quit xmonad
      ((modm .|. shiftMask, xK_q), io (exitWith ExitSuccess)),
      -- Restart xmonad
      ((modm .|. shiftMask, xK_r), spawn "xmonad --recompile; xmonad --restart"),
      -- Run xmessage with a summary of the default keybindings (useful for beginners)
      ((modm .|. shiftMask, xK_slash), spawn ("echo \"" ++ "\" | xmessage -file -"))
    ]
      -- mod-[1..9], Switch to workspace N
      -- mod-shift-[1..9], Move client to workspace N
      --
      ++ [ ((m .|. modm, k), windows $ f i)
           | (i, k) <- zip (XMonad.workspaces conf) [xK_1 .. xK_9],
             (f, m) <- [(W.greedyView, 0), (W.shift, shiftMask)]
         ]
      -- a basic CycleWS setup
      ++ [ ((modm, xK_i), nextWS),
           ((modm, xK_u), prevWS)
         ]

-- mod-{w,e,r}, Switch to physical/Xinerama screens 1, 2, or 3
-- mod-shift-{w,e,r}, Move client to screen 1, 2, or 3
--
-- ++
-- [((m .|. modm, key), screenWorkspace sc >>= flip whenJust (windows . f))
--     | (key, sc) <- zip [xK_w, xK_e, xK_r] [0..]
--     , (f, m) <- [(W.view, 0), (W.shift, shiftMask)]]

------------------------------------------------------------------------
-- Mouse bindings: default actions bound to mouse events
--
myMouseBindings (XConfig {XMonad.modMask = modm}) =
  M.fromList $
    -- mod-button1, Set the window to floating mode and move by dragging
    [ ( (modm, button1),
        ( \w ->
            focus w >> mouseMoveWindow w
              >> windows W.shiftMaster
        )
      ),
      -- mod-button2, Raise the window to the top of the stack
      ((modm, button2), (\w -> focus w >> windows W.shiftMaster)),
      -- mod-button3, Set the window to floating mode and resize by dragging
      ( (modm, button3),
        ( \w ->
            focus w >> mouseResizeWindow w
              >> windows W.shiftMaster
        )
      )
      -- you may also bind events to the mouse scroll wheel (button4 and button5)
    ]

------------------------------------------------------------------------
-- Layouts:

-- You can specify and transform your layouts by modifying these values.
-- If you change layout bindings be sure to use 'mod-shift-space' after
-- restarting (with 'mod-q') to reset your layout state to the new
-- defaults, as xmonad preserves your old layout settings by default.
--
-- The available layouts.  Note that each layout is separated by |||,
-- which denotes layout choice.
--
-- Makes setting the spacingRaw simpler to write.
-- The spacingRaw module adds a configurable amount of space around windows.
mySpacing :: Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing i = spacingRaw False (Border i i i i) True (Border i i i i) True

tall = renamed [Replace "tall"]
    $ windowNavigation
    $ addTabs shrinkText myTabTheme
    $ limitWindows 12
    $ mySpacing 8
    $ ResizableTall 1 (3/100) (1/2) []

full = renamed [Replace "full"]
    $ windowNavigation
    $ addTabs shrinkText myTabTheme
    $ limitWindows 20
    $ mySpacing 8
    $ Full

grid = renamed [Replace "grid"]
    $ windowNavigation
    $ addTabs shrinkText myTabTheme
    $ limitWindows 12
    $ mySpacing 8
    $ Grid (16 / 10)

mirror = renamed [Replace "mirror"]
    $ windowNavigation
    $ addTabs shrinkText myTabTheme
    $ limitWindows 12
    $ mySpacing 8
    $ Mirror(Tall 1 (3/100) (3/5))

-- setting colors for tabs layout and tabs sublayout.
myTabTheme =
  def
    { fontName = myFont,
      activeColor = "#46d9ff",
      inactiveColor = "#313846",
      activeTextColor = "#282c34",
      inactiveTextColor = "#d0d0d0"
    }

myLayoutHook = avoidStruts $ windowArrange $ smartBorders $ myDefaultLayout
  where
    myDefaultLayout = tall
        ||| grid
        ||| full
        ||| mirror

------------------------------------------------------------------------
-- Window rules:

-- Execute arbitrary actions and WindowSet manipulations when managing
-- a new window. You can use this to, for example, always float a
-- particular program, or have a client always appear on a particular
-- workspace.
--
-- To find the property name associated with a program, use
-- > xprop | grep WM_CLASS
-- and click on the client you're interested in.
--
-- To match on the WM_NAME, you can use 'title' in the same way that
-- 'className' and 'resource' are used below.
--
myManageHook :: XMonad.Query (Data.Monoid.Endo WindowSet)
myManageHook =
  composeAll
    [ className =? "MPlayer" --> doFloat,
      className =? "Gimp" --> doFloat,
      className =? "Android Emulator - Pixel_3a_API_33_x86_64:5554" --> doFloat,
      resource =? "desktop_window" --> doIgnore,
      resource =? "kdesktop" --> doIgnore,
      className =? "Pavucontrol" --> doFloat,
      className =? "peek" --> doFloat,
      className =? "flameshot" --> doFloat,
      className =? "Slack" --> doShift (myWorkspaces !! 8),
      className =? "Emacs" --> doShift (myWorkspaces !! 0),
      className =? "zoom" --> doFloat,
      className =? "zoom" --> doShift (myWorkspaces !! 4)
    ]

------------------------------------------------------------------------
-- Event handling

-- * EwmhDesktops users should change this to ewmhDesktopsEventHook

--
-- Defines a custom handler function for X Events. The function should
-- return (All True) if the default handler is to be run afterwards. To
-- combine event hooks use mappend or mconcat from Data.Monoid.
--
-- myEventHook = mempty

------------------------------------------------------------------------
-- Status bars and logging

-- Perform an arbitrary action on each internal state change or X event.
-- See the 'XMonad.Hooks.DynamicLog' extension for examples.
--
myFadeHook = composeAll [opaque, isUnfocused --> transparency 0.2]

myLogHook :: X ()
myLogHook = fadeWindowsLogHook myFadeHook

------------------------------------------------------------------------
-- Startup hook

-- Perform an arbitrary action each time xmonad starts or is restarted
-- with mod-q.  Used by, e.g., XMonad.Layout.PerWorkspace to initialize
-- per-workspace layout choices.
--
-- By default, do nothing.
myStartupHook :: X ()
myStartupHook = do
  spawnOnce "setxkbmap -option 'caps:ctrl_modifier'"
  spawnOnce "~/.screenlayout/lenovo.sh"
  spawnOnce "xwallpaper --stretch ~/wallpapers/wall.jpg"
  spawnOnce "picom --config ~/.config/picom.conf --experimental-backends"
  spawnOnce "dunst &"
  spawnOnce "xfce4-power-manager &"
  spawnOnce "/usr/local/bin/emacs &"

------------------------------------------------------------------------
-- Now run xmonad with all the defaults we set up.

-- Run xmonad with the settings you specify. No need to modify this.
--
main :: IO ()
main = do
  xmproc <- spawnPipe "xmobar ~/.config/xmobar/xmobarrc"
  xmonad $
    ewmh
      def
        { -- simple stuff
          terminal = myTerminal,
          focusFollowsMouse = myFocusFollowsMouse,
          clickJustFocuses = myClickJustFocuses,
          borderWidth = myBorderWidth,
          modMask = myModMask,
          workspaces = myWorkspaces,
          normalBorderColor = myNormalBorderColor,
          focusedBorderColor = myFocusedBorderColor,
          -- key bindings
          keys = myKeys,
          mouseBindings = myMouseBindings,
          -- hooks, layouts
          layoutHook = myLayoutHook,
          startupHook = myStartupHook,
          manageHook = (isFullscreen --> doFullFloat) <+> myManageHook <+> manageDocks,
          handleEventHook = docksEventHook,
          logHook =
            myLogHook
              <+> dynamicLogWithPP
                xmobarPP
                  { ppOutput = hPutStrLn xmproc,
                    ppCurrent = xmobarColor "red" "" . wrap "→ " "", -- Current workspace in xmobar
                    ppVisible = xmobarColor "white" "", -- Visible but not current workspace
                    ppHidden = xmobarColor "white" "" . wrap "" "°", -- Hidden workspaces in xmobar
                    ppHiddenNoWindows = xmobarColor "white" "", -- Hidden workspaces (no windows)
                    ppSep = " | ", -- Separators in xmobar
                    ppUrgent = xmobarColor "#C45500" "" . wrap "!" "!", -- Urgent workspace
                    -- , ppTitle = xmobarColor "#b3afc2" "" . shorten 60     -- Title of active window in xmobar
                    -- , ppOrder  = \(ws:l:t:ex) -> [ws]++ex++[t]
                    ppOrder = \(ws : l : t : ex) -> [ws] ++ ex
                  }
        }
      `additionalKeys` myAdditionalKeys
