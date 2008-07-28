/*
 * AKAppController.m
 *
 * Created by Andy Lee on Thu Jun 27 2002.
 * Copyright (c) 2003, 2004 Andy Lee. All rights reserved.
 */

#import "AKAppController.h"

#import <CoreFoundation/CoreFoundation.h>
#import <DIGSLog.h>
#import <DIGSFindBuffer.h>

#import "AKFrameworkSetup.h"

#import "AKDocSetIndex.h"
#import "AKDocSetBasedFramework.h"
#import "AKFrameworkConstants.h"
#import "AKTextUtils.h"
#import "AKViewUtils.h"
#import "AKPrefUtils.h"
#import "AKDevToolsUtils.h"
#import "AKDebugUtils.h"
#import "AKDatabase.h"
#import "AKDatabaseXMLExporter.h"
#import "AKCocoaFramework.h"
#import "AKDocLocator.h"
#import "AKPrefPanelController.h"
#import "AKQuicklistController.h"
#import "AKWindowController.h"
#import "AKWindowLayout.h"
#import "AKSavedWindowState.h"
#import "AKTopic.h"

#import "AKDocPathsPrefPanelController.h"


// [agl] working on parse performance
#define MEASURE_PARSE_SPEED 1

//-------------------------------------------------------------------------
// Forwarding of applescript commands
//-------------------------------------------------------------------------

// Thanks to Dominik Wagner for AppleScript support!

@interface NSApplication (NSAppScriptingAdditions) 
- (id)handleSearchScriptCommand:(NSScriptCommand *)aCommand;
@end


@implementation NSApplication (NSAppScriptingAdditions) 

- (id)handleSearchScriptCommand:(NSScriptCommand *)aCommand
{
    return [[AKAppController sharedInstance] handleSearchScriptCommand:aCommand];
}

@end


//-------------------------------------------------------------------------
// Forward declarations of private methods
//-------------------------------------------------------------------------

@interface AKAppController (Private)

//-------------------------------------------------------------------------
// Private methods -- steps during launch
//-------------------------------------------------------------------------

- (void)_initAboutPanel;
- (BOOL)_containsRequiredFrameworks:(AKFrameworkSetup *)fwSetup;
- (void)_initGoMenu;
- (void)_maybeAddDebugMenu;  // [agl] uses AKDebugUtils

//-------------------------------------------------------------------------
// Private methods -- version management
//-------------------------------------------------------------------------

- (NSString *)_appVersion;

- (NSDictionary *)_latestAppVersion;

- (BOOL)_version:(NSDictionary *)lhs isNewerThan:(NSDictionary *)rhs;
- (NSComparisonResult)_compareValuesForKey:(NSString *)key
    forLHS:(NSDictionary *)lhs
    andRHS:(NSDictionary *)rhs
    nilIsGreatest:(BOOL)nilIsGreatest;

- (NSDictionary *)_versionDictionaryFromString:(NSString *)versionString;
- (NSString *)_displayStringForVersion:(NSDictionary *)versionDictionary;

//-------------------------------------------------------------------------
// Private methods -- window management
//-------------------------------------------------------------------------

- (AKWindowController *)_newWindowControllerWithLayout:(AKWindowLayout *)windowLayout;
- (void)_handleWindowWillCloseNotification:(NSNotification *)notification;
- (void)_openInitialWindows;
- (NSArray *)_allWindowsAsPrefArray;

//-------------------------------------------------------------------------
// Private methods -- Favorites
//-------------------------------------------------------------------------

- (void)_getFavoritesFromPrefs;
- (void)_putFavoritesIntoPrefs;
- (void)_updateFavoritesMenu;

@end

@implementation AKAppController

//-------------------------------------------------------------------------
// Private constants
//-------------------------------------------------------------------------

// [agl] handle the possibility of hosting elsewhere; make a pref?
// URL of the downloads page for AppKiDo.
static NSString *_AKHomePageURL =
                            @"http://homepage.mac.com/aglee/downloads";

// URL of the file from which to get the latest version number.
static NSString *_AKVersionURL =
            @"http://homepage.mac.com/aglee/downloads/AppKiDo.version";

// Dictionary keys.
static NSString *_AKMajorNumberKey      = @"major";
static NSString *_AKMinorNumberKey      = @"minor";
static NSString *_AKPatchNumberKey      = @"patch";
static NSString *_AKSneakyPeekNumberKey = @"sneakypeek";

//-------------------------------------------------------------------------
// Factory methods
//-------------------------------------------------------------------------

static id s_sharedInstance = nil;  // Value will be set by -init.

+ (id)sharedInstance
{
    return s_sharedInstance;
}

//-------------------------------------------------------------------------
// Init/awake/dealloc
//-------------------------------------------------------------------------


// [agl] working on performance
#if MEASURE_PARSE_SPEED
static NSTimeInterval g_startTime = 0.0;
static NSTimeInterval g_checkpointTime = 0.0;

- (void)_timeParseStart
{
    g_startTime = [NSDate timeIntervalSinceReferenceDate];
    g_checkpointTime = g_startTime;
    NSLog(@"---------------------------------");
    NSLog(@"START: about to parse...");
}

- (void)_timeParseCheckpoint:(NSString *)description
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSLog(@"...CHECKPOINT: %@", description);
    NSLog(@"               %.3f seconds since last checkpoint",
        now - g_checkpointTime);
    g_checkpointTime = now;
}

- (void)_timeParseEnd
{
    NSLog(@"...DONE: took %.3f seconds total",
        [NSDate timeIntervalSinceReferenceDate] - g_startTime);
}
#endif MEASURE_PARSE_SPEED

- (id)init
{
    if ((self = [super init]))
    {
        _finishedInitializing = NO;
        _windowControllers = [[NSMutableArray alloc] init];
        _favoritesList = [[NSMutableArray alloc] init];

        // It's okay to assume this class will be instantiated exactly once.
        s_sharedInstance = self;
    }

    return self;
}

- (void)awakeFromNib
{
    // Initialize the About panel.
    [self _initAboutPanel];

    // Get the list of supported frameworks, using the user's prefs to
    // figure out where to get that list.  Prompt the user repeatedly if
    // necessary to either get valid values for those prefs or quit the app.
    while ((_frameworkSetup = [AKFrameworkSetup frameworkSetupBasedOnPrefs]) == nil)
    {
        if (![[AKDocPathsPrefPanelController sharedInstance] runPanel])
        {
            [NSApp terminate:nil];
        }
    }
    [_frameworkSetup retain];

    // Put up the splash window.
    [_splashVersionField setStringValue:[self _appVersion]];
    [_splashWindow setReleasedWhenClosed:YES];
    [_splashWindow center];
    [_splashWindow makeKeyAndOrderFront:nil];

    // Populate the database by parsing files for each of the selected
    // frameworks in the user's prefs.
    [_splashMessageField setStringValue:@"Parsing files for framework:"];
    [_splashMessageField display];

// [agl] working on performance
#if MEASURE_PARSE_SPEED
[self _timeParseStart];
#endif MEASURE_PARSE_SPEED

    AKDatabase *db = [AKDatabase defaultDatabase];
    NSEnumerator *en = [[AKPrefUtils selectedFrameworkNamesPref] objectEnumerator];
    NSString *fwName;
    while ((fwName = [en nextObject]))
    {
        AKFramework *fw = [_frameworkSetup frameworkNamed:fwName];
        
        if (fw)
        {
            [_splashMessage2Field setStringValue:fwName];
            [_splashMessage2Field display];

            [fw populateDatabase:db];
        }
    }

// [agl] working on performance
#if MEASURE_PARSE_SPEED
[self _timeParseEnd];
#endif MEASURE_PARSE_SPEED

    [_splashMessage2Field setStringValue:@""];
    [_splashMessage2Field display];

    // Update the "Go" menu.
    [self _initGoMenu];

    // Grab the Favorites list from the user preferences.
    [self _getFavoritesFromPrefs];

    // Take down the splash window.
    [_splashWindow close];
    _splashWindow = nil;
    _splashVersionField = nil;
    _splashMessageField = nil;
    _splashMessage2Field = nil;

    // Register interest in window-close events.
    [[NSNotificationCenter defaultCenter]
        addObserver:self
        selector:@selector(_handleWindowWillCloseNotification:)
        name:NSWindowWillCloseNotification object:nil];

    // Force the DIGSFindBuffer to initialize.
    // [agl] ??? Why not in DIGSFindBuffer's +initialize?
    (void)[DIGSFindBuffer sharedInstance];

    // Proceed to our main business.
    [self _openInitialWindows];

    // Add the Debug menu if certain conditions are met.
    [self _maybeAddDebugMenu];  // [agl] uses AKDebugUtils

    _finishedInitializing = YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [_frameworkSetup release];
    [_windowControllers release];
    [_favoritesList release];

    [super dealloc];
}

//-------------------------------------------------------------------------
// Getters and setters
//-------------------------------------------------------------------------

- (AKFrameworkSetup *)frameworkSetup
{
    return _frameworkSetup;
}

//-------------------------------------------------------------------------
// Navigation
//-------------------------------------------------------------------------

// [agl] what about using [NSView +focusView]?
- (NSTextView *)selectedTextView
{
    id obj = [[NSApp keyWindow] firstResponder];

    return (obj && [obj isKindOfClass:[NSTextView class]]) ? obj : nil;
}

// [agl] Was there some reason I couldn't use keyWindow/mainWindow instead of
// iterating through the whole window list?
- (AKWindowController *)frontmostWindowController
{
    int numWindows;

    NSCountWindows(&numWindows);

    int windowList[numWindows];

    NSWindowList(numWindows, windowList);

    int i;
    for (i = 0; i < numWindows; i++)
    {
        int windowNum = windowList[i];
        NSWindow *win = [NSApp windowWithWindowNumber:windowNum];
        id del = [win delegate];

        if ([del isKindOfClass:[AKWindowController class]])
        {
            return del;
        }
    }

    // If we got this far, there is no browser window open.
    return nil;
}

- (AKWindowController *)openNewWindow
{
    NSDictionary *prefDict =
        [AKPrefUtils
            dictionaryValueForPref:AKLayoutForNewWindowsPrefName];
    AKWindowLayout *windowLayout =
        [AKWindowLayout fromPrefDictionary:prefDict];
    AKWindowController *windowController =
        [self _newWindowControllerWithLayout:windowLayout];

    [windowController
        openWindowWithQuicklistDrawer:
            (windowLayout
            ? [windowLayout quicklistDrawerIsOpen]
            : YES)];

    return windowController;
}

//-------------------------------------------------------------------------
// Preferences
//-------------------------------------------------------------------------

- (void)applyUserPreferences
{
    // Apply the newly saved preferences to all open windows.
    NSEnumerator *en = [_windowControllers objectEnumerator];
    AKWindowController *wc;

    while ((wc = [en nextObject]))
    {
        if (![wc isKindOfClass:[AKWindowController class]])
        {
            DIGSLogError(
                @"_windowControllers contains a non-AKWindowController");
        }
        else
        {
            [wc applyUserPreferences];
        }
    }
}

//-------------------------------------------------------------------------
// AppleScript support
//-------------------------------------------------------------------------

- (id)handleSearchScriptCommand:(NSScriptCommand *)aCommand
{
    AKWindowController *wc = [self openNewWindow];
    [wc searchForString:[aCommand directParameter]];
    return nil;
}

//-------------------------------------------------------------------------
// Managing the user's Favorites list
//-------------------------------------------------------------------------

- (NSArray *)favoritesList
{
    return _favoritesList;
}

- (void)addFavorite:(AKDocLocator *)docLocator
{
    // Only add the item if it's not already there.
    if ((docLocator != nil) && ![_favoritesList containsObject:docLocator])
    {
        [_favoritesList addObject:docLocator];
        [self _putFavoritesIntoPrefs];
        [self applyUserPreferences];
    }
}

- (void)removeFavoriteAtIndex:(int)index
{
    if (index >= 0)
    {
        [_favoritesList removeObjectAtIndex:index];
        [self _putFavoritesIntoPrefs];
        [self applyUserPreferences];
    }
}

- (void)moveFavoriteFromIndex:(int)fromIndex toIndex:(int)toIndex
{
    AKDocLocator *fav = [_favoritesList objectAtIndex:fromIndex];

    [fav retain];
    if (fromIndex > toIndex)
    {
        [_favoritesList removeObjectAtIndex:fromIndex];
        [_favoritesList insertObject:fav atIndex:toIndex];
    }
    else
    {
        [_favoritesList insertObject:fav atIndex:toIndex];
        [_favoritesList removeObjectAtIndex:fromIndex];
    }
    [fav release];
    [self _putFavoritesIntoPrefs];
    [self applyUserPreferences];
}

//-------------------------------------------------------------------------
// UI item validation
//-------------------------------------------------------------------------

- (BOOL)validateItem:(id)anItem
{
    SEL itemAction = [anItem action];

    if (itemAction == @selector(openSearchPanel:))
    {
        return YES;
    }
    else if ((itemAction == @selector(openNewWindow:))
        || (itemAction == @selector(openLinkInNewWindow:))
        || (itemAction == @selector(openPrefsPanel:))
        || (itemAction == @selector(checkForNewerVersion:))
        || (itemAction == @selector(openAboutPanel:))
        || (itemAction == @selector(exportDatabase:)))
    {
        return YES;
    }
    else if ((itemAction == @selector(_testParser:)) // [agl] uses AKDebugUtils
        || (itemAction == @selector(_printKeyViewLoop:)))
    {
        return YES;
    }
    else if (itemAction == @selector(scrollToTextSelection:))
    {
        NSTextView *tv = [self selectedTextView];

        if (tv == nil) { return NO; }

        return ([tv selectedRange].length > 0);
    }
    else
    {
        return NO;
    }
}

//-------------------------------------------------------------------------
// Action methods
//-------------------------------------------------------------------------

- (IBAction)openAboutPanel:(id)sender
{
    [_aboutPanel makeKeyAndOrderFront:nil];
}

- (IBAction)checkForNewerVersion:(id)sender
{
    // Phone home for the latest version number.
    NSDictionary *latestVersion = [self _latestAppVersion];

    if (latestVersion == nil)
    {
        return;
    }

    // See if the latest version is newer than what the user is running.
    NSDictionary *thisVersion =
        [self _versionDictionaryFromString:[self _appVersion]];

    if (![self _version:latestVersion isNewerThan:thisVersion])
    {
        NSRunAlertPanel(
            @"Up to date",  // title
            @"You have the latest version of AppKiDo.",  // msg
            @"OK",  // defaultButton
            nil,  // alternateButton
            nil);  // otherButton

        return;
    }

    // If we got this far, the user does not have the latest version.
    NSString *alertMessage =
        [NSString
            stringWithFormat:
                @"Version %@ of AppKiDo is available for download."
                @"  You are currently running version %@."
                @"\n\nWould you like to go to the AppKiDo web page?",
            [self _displayStringForVersion:latestVersion],
            [self _displayStringForVersion:thisVersion]];

    int whichButton =
        NSRunAlertPanel(
            @"Newer version available",  // title
            alertMessage,  // msg
            @"Yes, go to web site",  // defaultButton
            nil,  // alternateButton
            @"No");  // otherButton

    if (whichButton == NSAlertDefaultReturn)
    {
        [[NSWorkspace sharedWorkspace]
            openURL:[NSURL URLWithString:_AKHomePageURL]];
    }
}

- (IBAction)openPrefsPanel:(id)sender
{
    [[AKPrefPanelController sharedInstance] openPrefsPanel:sender];
}

- (IBAction)openNewWindow:(id)sender
{
    (void)[self openNewWindow];
}

// This is only called from the doc view's contextual menu, so it's
// not declared in the .h.
- (IBAction)openLinkInNewWindow:(id)sender
{
    if ([sender isKindOfClass:[NSMenuItem class]])
    {
        NSURL *linkURL = (NSURL *)[sender representedObject];
        AKWindowController *wc = [self openNewWindow];

        (void)[wc jumpToLinkURL:linkURL];
    }
}

- (IBAction)scrollToTextSelection:(id)sender
{
    NSTextView *textView = [self selectedTextView];

    if (textView)
    {
        [textView scrollRangeToVisible:[textView selectedRange]];
    }
}

- (IBAction)exportDatabase:(id)sender
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    NSString *defaultFilename =
        [NSString stringWithFormat:@"AppKiDo-DB-%@.xml",
            [self _appVersion]];

    int modalResult =
        [savePanel
            runModalForDirectory:NSHomeDirectory()
            file:defaultFilename];

    if (modalResult != NSFileHandlingPanelOKButton)
    {
        return;
    }

    BOOL fileOK =
        [[NSFileManager defaultManager]
            createFileAtPath:[savePanel filename]
            contents:nil
            attributes:nil];

    if (!fileOK)
    {
        DIGSLogExitingMethodPrematurely(
            ([NSString
                stringWithFormat:@"failed to get create file at [%@]",
                    [savePanel filename]]));
        return;
    }

    NSFileHandle *fh =
        [NSFileHandle fileHandleForUpdatingAtPath:[savePanel filename]];

    if (fh == nil)
    {
        DIGSLogExitingMethodPrematurely(
            ([NSString
                stringWithFormat:@"failed to get file handle for [%@]",
                    [savePanel filename]]));
        return;
    }

    AKDatabaseXMLExporter *exporter =
        [AKDatabaseXMLExporter exporterWithDefaultDatabase];
    [exporter exportToFileHandle:fh];
    [fh closeFile];
}

// [agl] uses AKDebugUtils
- (IBAction)_testParser:(id)sender
{
    [AKFileSectionDebug _testParser];
}

- (IBAction)_printKeyViewLoop:(id)sender
{
    id firstResponder = [[NSApp keyWindow] firstResponder];

    if (firstResponder == nil)
    {
        NSLog(@"there's no first responder");
    }
    else
    {
        NSLog(@"key window's first responder is %@ at 0x%x",
            [firstResponder className],
            firstResponder);

        if ([firstResponder isKindOfClass:[NSView class]])
        {
            [firstResponder ak_printKeyViewLoop];
            [firstResponder ak_printReverseKeyViewLoop];
        }
    }
}

//-------------------------------------------------------------------------
// NSMenuValidation protocol methods
//-------------------------------------------------------------------------

- (BOOL)validateMenuItem:(NSMenuItem *)aCell
{
    return [self validateItem:aCell];
}

//-------------------------------------------------------------------------
// NSToolbarItemValidation protocol methods
//-------------------------------------------------------------------------

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    return [self validateItem:theItem];
}

//-------------------------------------------------------------------------
// NSApplication delegate methods
//-------------------------------------------------------------------------

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    // Open a browser window if none is open.  Only do so if we've
    // finished setting up the database and other initialization we
    // need for the UI to work.
    if (_finishedInitializing)
    {
        AKWindowController *wc = [self frontmostWindowController];

        if (wc == nil)
        {
            [self openNewWindow];
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Update prefs with the state of all open windows.
    [AKPrefUtils
        setArrayValue:[self _allWindowsAsPrefArray]
        forPref:AKSavedWindowStatesPrefName];
}

@end


//-------------------------------------------------------------------------
// Private methods
//-------------------------------------------------------------------------

@implementation AKAppController (Private)

//-------------------------------------------------------------------------
// Private methods -- steps during launch
//-------------------------------------------------------------------------

- (void)_initAboutPanel
{
    [_aboutPanel center];

    // Load the version string text field.
    [_aboutVersionField setStringValue:[self _appVersion]];

    // Load the credits text field.
    NSString *creditsPath =
        [[NSBundle mainBundle]
            pathForResource:@"Credits"
            ofType:@"html"];
    NSAttributedString *creditsString =
        [[[NSAttributedString alloc]
            initWithPath:creditsPath
                documentAttributes:(NSDictionary **)NULL]
            autorelease];

    [[_aboutCreditsView textStorage] setAttributedString:creditsString];
}

// If we can't find files for either Foundation or AppKit, offer the user the
// choice of either quitting or re-specifying the location of the Dev Tools.
// Returns YES if Foundation and AppKit were found, NO if one of them was
// not found.
- (BOOL)_containsRequiredFrameworks:(AKFrameworkSetup *)fwSetup
{
    NSArray *namesOfAvailableFrameworks =
        [fwSetup namesOfAvailableFrameworks];

    if ([namesOfAvailableFrameworks containsObject:AKFoundationFrameworkName]
        && [namesOfAvailableFrameworks containsObject:AKAppKitFrameworkName])
    {
        return YES;
    }
    else
    {
        int alertResult =
            NSRunAlertPanel(
                @"Missing documentation", // title,
                @"Either Foundation or AppKit documentation is missing from %@."
                @"\n"
                @"You may need to either:\n"
                @"\n"
                @"* go into Xcode's Documentation window and update the"
                @" Core Reference docset, or\n"
                @"\n"
                @"* specify the correct location of your Dev Tools.", // msg
                @"Quit AppKiDo", // defaultButton
                @"Locate Dev Tools", // alternateButton
                nil, // otherButton
                [AKPrefUtils devToolsPathPref]);

        if (alertResult == NSAlertDefaultReturn)
        {
            [NSApp terminate:nil];
            return NO;
        }
        else
        {
            return NO;
        }
    }
}

- (void)_initGoMenu
{
    NSMenu *goMenu = [_firstGoMenuDivider menu];
    int menuIndex = [goMenu indexOfItem:_firstGoMenuDivider];

    AKDatabase *db = [AKDatabase defaultDatabase];
    NSEnumerator *fwNameEnum = [[db sortedFrameworkNames] objectEnumerator];
    NSString *fwName;

    while ((fwName = [fwNameEnum nextObject]))
    {
        // See what information we have for this framework.
        NSArray *formalProtocolNodes = [db formalProtocolsForFramework:fwName];
        NSArray *informalProtocolNodes = [db informalProtocolsForFramework:fwName];
        NSArray *functionsGroupNodes = [db functionsGroupsForFramework:fwName];
        NSArray *globalsGroupNodes = [db globalsGroupsForFramework:fwName];

        // Construct the submenu of framework-related topics.
        NSMenu *fwTopicSubmenu =
            [[[NSMenu alloc] initWithTitle:fwName] autorelease];

        if ([formalProtocolNodes count] > 0)
        {
            NSMenuItem *subitem =
                [[[NSMenuItem alloc]
                    initWithTitle:AKProtocolsTopicName
                    action:@selector(jumpToFrameworkFormalProtocols:)
                    keyEquivalent:@""]
                    autorelease];

            [fwTopicSubmenu addItem:subitem];
        }

        if ([informalProtocolNodes count] > 0)
        {
            NSMenuItem *subitem =
                [[[NSMenuItem alloc]
                    initWithTitle:AKInformalProtocolsTopicName
                    action:@selector(jumpToFrameworkInformalProtocols:)
                    keyEquivalent:@""]
                    autorelease];

            [fwTopicSubmenu addItem:subitem];
        }

        if ([functionsGroupNodes count] > 0)
        {
            NSMenuItem *subitem =
                [[[NSMenuItem alloc]
                    initWithTitle:AKFunctionsTopicName
                    action:@selector(jumpToFrameworkFunctions:)
                    keyEquivalent:@""]
                    autorelease];

            [fwTopicSubmenu addItem:subitem];
        }

        if ([globalsGroupNodes count] > 0)
        {
            NSMenuItem *subitem =
                [[[NSMenuItem alloc]
                    initWithTitle:AKGlobalsTopicName
                    action:@selector(jumpToFrameworkGlobals:)
                    keyEquivalent:@""]
                    autorelease];

            [fwTopicSubmenu addItem:subitem];
        }

        // Construct the menu item to add to the Go menu, and add it.
        NSMenuItem *fwMenuItem =
            [[[NSMenuItem alloc]
                initWithTitle:fwName
                action:nil
                keyEquivalent:@""]
                autorelease];

        [fwMenuItem setSubmenu:fwTopicSubmenu];
        menuIndex++;
        [goMenu insertItem:fwMenuItem atIndex:menuIndex];
    }
}

// [agl] uses AKDebugUtils
// Add the Debug menu if the user is "Andy Lee" with login name "alee".
- (void)_maybeAddDebugMenu
{
    if ([NSUserName() isEqualToString:@"alee"]
        && [NSFullUserName() isEqualToString:@"Andy Lee"])
    {
        // Create the "Debug" top-level menu item.
        NSMenu *mainMenu = [NSApp mainMenu];
        NSMenuItem *debugMenuItem =
            [mainMenu
                addItemWithTitle:@"Debug"
                action:@selector(_testParser:)
                keyEquivalent:@""];
        [debugMenuItem setEnabled:YES];

        // Create the submenu that will be under the "Debug" top-level menu item.
        NSMenu *debugSubmenu =
            [[[NSMenu alloc] initWithTitle:@"Debug"] autorelease];
        [debugSubmenu setAutoenablesItems:YES];

        [debugSubmenu addItemWithTitle:@"Open Parser Testing Window"
                action:@selector(_testParser:)
                keyEquivalent:@""];
        [debugSubmenu addItemWithTitle:@"Print Key View Loop"
                action:@selector(_printKeyViewLoop:)
                keyEquivalent:@""];

        // Attach the submenu to the "Debug" top-level menu item.
        [mainMenu setSubmenu:debugSubmenu forItem:debugMenuItem];
    }
}

//-------------------------------------------------------------------------
// Private methods -- window management
//-------------------------------------------------------------------------

- (AKWindowController *)_newWindowControllerWithLayout:(AKWindowLayout *)windowLayout
{
    AKWindowController *windowController =
        [[[AKWindowController alloc] init] autorelease];

    [_windowControllers addObject:windowController];
    if (windowLayout)
    {
        [windowController takeWindowLayoutFrom:windowLayout];
    }

    return windowController;
}

- (void)_handleWindowWillCloseNotification:(NSNotification *)notification
{
    id windowDelegate = [(NSWindow *)[notification object] delegate];

    if ([windowDelegate isKindOfClass:[AKWindowController class]])
    {
        [_windowControllers removeObjectIdenticalTo:windowDelegate];
    }
}

- (void)_openInitialWindows
{
    NSArray *savedWindows =
        [AKPrefUtils arrayValueForPref:AKSavedWindowStatesPrefName];

    if ([savedWindows count] == 0)
    {
        (void)[self openNewWindow];
    }
    else
    {
        int numWindows = [savedWindows count];
        int i;

        for (i = numWindows - 1; i >= 0; i--)
        {
            NSDictionary *prefDict = [savedWindows objectAtIndex:i];
            AKSavedWindowState *savedWindowState =
                [AKSavedWindowState fromPrefDictionary:prefDict];
            AKWindowLayout *windowLayout =
                [savedWindowState savedWindowLayout];
            AKWindowController *wc =
                [self _newWindowControllerWithLayout:windowLayout];

            [wc jumpToDocLocator:[savedWindowState savedDocLocator]];
            [wc openWindowWithQuicklistDrawer:
                [windowLayout quicklistDrawerIsOpen]];
        }
    }
}

// takes snapshot of all open windows, returns array of dictionaries
// suitable for NSUserDefaults
- (NSArray *)_allWindowsAsPrefArray
{
    NSMutableArray *result = [NSMutableArray array];
    int numWindows;

    NSCountWindows(&numWindows);

    int windowList[numWindows];

    NSWindowList(numWindows, windowList);

    int i;
    for (i = 0; i < numWindows; i++)
    {
        int windowNum = windowList[i];
        NSWindow *win = [NSApp windowWithWindowNumber:windowNum];
        id del = [win delegate];

        if ([del isKindOfClass:[AKWindowController class]])
        {
            AKWindowController *wc = (AKWindowController *)del;
            AKSavedWindowState *savedWindowState =
                [[[AKSavedWindowState alloc] init] autorelease];

            [wc putSavedWindowStateInto:savedWindowState];
            [result addObject:[savedWindowState asPrefDictionary]];
        }
    }

    return result;
}

//-------------------------------------------------------------------------
// Private methods -- version management
//-------------------------------------------------------------------------

- (NSString *)_appVersion
{
    return
        [[[NSBundle mainBundle] infoDictionary]
            objectForKey:@"CFBundleVersion"];
}

// AppKiDoVersion##X.YY or X.YYZ or X.YYZspWW
//  X  is major (1 or more digits)
//  YY is minor version number (exactly 2 digits)
//  Z  is patch number, if present (exactly 1 digit)
//  WW is sneakypeek number, if present (unpadded integer)
- (NSDictionary *)_latestAppVersion
{
    NSURL *latestAppVersionURL = [NSURL URLWithString:_AKVersionURL];
/*
    NSString *pathString =
        @"file://Users/alee/_Programming/AppKiDo-0.90/AppKiDo.version";
    NSURL *latestAppVersionURL = [NSURL URLWithString:pathString];
*/

    NSString *latestAppVersionString =
        [[NSString stringWithContentsOfURL:latestAppVersionURL]
            ak_trimWhitespace];

    if (latestAppVersionString == nil)
    {
        NSRunAlertPanel(
            @"Problem phoning home",  // title
            @"Couldn't access the version number from the"
            @" AppKiDo web site.",  // msg
            @"OK",  // defaultButton
            nil,  // alternateButton
            nil);  // otherButton


        return nil;
    }

    NSString *expectedPrefix = @"AppKiDoVersion";

    if ((![latestAppVersionString hasPrefix:expectedPrefix])
        || ([latestAppVersionString length] > 30))
    {
        DIGSLogWarning(
            @"the received contents of the version-number URL don't"
            @" look like a valid version string");
        return nil;
    }

    latestAppVersionString =
        [latestAppVersionString
            substringFromIndex:[expectedPrefix length]];

    return [self _versionDictionaryFromString:latestAppVersionString];
}

- (BOOL)_version:(NSDictionary *)lhs isNewerThan:(NSDictionary *)rhs
{
    NSComparisonResult comparison;

    // Compare the major version numbers.
    comparison =
        [self
            _compareValuesForKey:_AKMajorNumberKey
            forLHS:lhs
            andRHS:rhs
            nilIsGreatest:NO];

    if (comparison == NSOrderedDescending)
    {
        return YES;
    }
    else if (comparison == NSOrderedAscending)
    {
        return NO;
    }

    // Compare the minor version numbers.
    comparison =
        [self
            _compareValuesForKey:_AKMinorNumberKey
            forLHS:lhs
            andRHS:rhs
            nilIsGreatest:NO];

    if (comparison == NSOrderedDescending)
    {
        return YES;
    }
    else if (comparison == NSOrderedAscending)
    {
        return NO;
    }

    // Compare the patch version numbers, if they are present.
    comparison =
        [self
            _compareValuesForKey:_AKPatchNumberKey
            forLHS:lhs
            andRHS:rhs
            nilIsGreatest:NO];

    if (comparison == NSOrderedDescending)
    {
        return YES;
    }
    else if (comparison == NSOrderedAscending)
    {
        return NO;
    }

    // Compare the sneakypeek version numbers, if they are present.
    comparison =
        [self
            _compareValuesForKey:_AKSneakyPeekNumberKey
            forLHS:lhs
            andRHS:rhs
            nilIsGreatest:YES];

    if (comparison == NSOrderedDescending)
    {
        return YES;
    }
    else if (comparison == NSOrderedAscending)
    {
        return NO;
    }

    // If we got this far, all components matched.
    return NO;
}

// If nilIsGreatest, then nil is "greater than" anything except itself.
// Otherwise, nil is "less than" anything except itself.
- (NSComparisonResult)_compareValuesForKey:(NSString *)key
    forLHS:(NSDictionary *)lhs
    andRHS:(NSDictionary *)rhs
    nilIsGreatest:(BOOL)nilIsGreatest
{
    NSString *lhsValue = [lhs objectForKey:key];
    NSString *rhsValue = [rhs objectForKey:key];

    if ([@"" isEqualToString:lhsValue])
    {
        lhsValue = nil;
    }

    if ([@"" isEqualToString:rhsValue])
    {
        rhsValue = nil;
    }

    // Handle cases where values are identical, possibly by being nil.
    if (lhsValue == rhsValue)
    {
        return NSOrderedSame;
    }

    // If we got this far, we have at least one non-nil value.
    // Rule out the remaining nil cases.
    if (lhsValue == nil)
    {
        return nilIsGreatest ? NSOrderedDescending : NSOrderedAscending;
    }

    if (rhsValue == nil)
    {
        return nilIsGreatest ? NSOrderedAscending : NSOrderedDescending;
    }

    // If we got this far, we have two different non-nil values.
    return [lhsValue compare:rhsValue];
}

- (NSDictionary *)_versionDictionaryFromString:(NSString *)versionString
{
    NSArray *versionParts = nil;

    // Parse out the major version number.
    versionParts = [versionString componentsSeparatedByString:@"."];

    if ([versionParts count] != 2)
    {
        DIGSLogWarning(@"error parsing major/minor version numbers");
        return nil;
    }

    NSString *majorNumber = [versionParts objectAtIndex:0];
    NSString *minorNumber = [versionParts objectAtIndex:1];

    // Parse out the sneakypeek number if it's there.
    versionParts = [minorNumber componentsSeparatedByString:@"sp"];

    if ([versionParts count] > 2)
    {
        DIGSLogWarning(@"error parsing sneakypeek version number");
        return nil;
    }

    NSString *sneakypeekNumber = @"";

    if ([versionParts count] == 2)
    {
        minorNumber = [versionParts objectAtIndex:0];
        sneakypeekNumber = [versionParts objectAtIndex:1];
    }

    // Parse out the patch number if it's there.
    if (([minorNumber length] < 2) || ([minorNumber length] > 3))
    {
        DIGSLogWarning(@"error parsing minor/patch version numbers");
        return nil;
    }

    NSString *patchNumber = @"";

    if ([minorNumber length] == 3)
    {
        patchNumber = [minorNumber substringFromIndex:2];
        minorNumber = [minorNumber substringToIndex:2];
    }    

    // Stuff the parts of the version string into a dictionary.
    NSMutableDictionary *versionDictionary =
        [NSMutableDictionary dictionary];

    [versionDictionary
        setObject:majorNumber
        forKey:_AKMajorNumberKey];
    [versionDictionary
        setObject:minorNumber
       forKey:_AKMinorNumberKey];
    [versionDictionary
        setObject:patchNumber
        forKey:_AKPatchNumberKey];
    [versionDictionary
        setObject:sneakypeekNumber
        forKey:_AKSneakyPeekNumberKey];

    return versionDictionary;
}

- (NSString *)_displayStringForVersion:(NSDictionary *)versionDictionary
{
    // Concatenate the major and minor version numbers.
    NSString *versionString =
        [NSString
            stringWithFormat:@"%@.%@",
            [versionDictionary objectForKey:_AKMajorNumberKey],
            [versionDictionary objectForKey:_AKMinorNumberKey]];

    // See if there is a patch number.
    NSString *patchNumber =
        [versionDictionary objectForKey:_AKPatchNumberKey];

    if (patchNumber && ([patchNumber length] > 0))
    {
        versionString =
            [versionString stringByAppendingString:patchNumber];
    }

    // See if there is a sneakypeek number.
    NSString *sneakypeekNumber =
        [versionDictionary objectForKey:_AKSneakyPeekNumberKey];

    if (sneakypeekNumber && ([sneakypeekNumber length] > 0))
    {
        versionString =
            [NSString
                stringWithFormat:@"%@sp%@",
                versionString,
                sneakypeekNumber];
    }

    // Return the result.
    return versionString;
}

//-------------------------------------------------------------------------
// Private methods -- Favorites
//-------------------------------------------------------------------------

- (void)_getFavoritesFromPrefs
{
    NSArray *favPrefList =
        [AKPrefUtils arrayValueForPref:AKFavoritesPrefName];
    int numFavs = [favPrefList count];
    int i;

    // Get values from NSUserDefaults.
    [_favoritesList removeAllObjects];
    BOOL someFavsWereInvalid = NO;
    for (i = 0; i < numFavs; i++)
    {
        id favPref = [favPrefList objectAtIndex:i];
        AKDocLocator *favItem = [AKDocLocator fromPrefDictionary:favPref];

        // It is possible for a Favorite to be invalid if the user has
        // chosen to exclude the framework the Favorite belongs to.
        if ([favItem stringToDisplayInLists])
        {
            [_favoritesList addObject:favItem];
        }
        else
        {
            someFavsWereInvalid = YES;
        }
    }
    if (someFavsWereInvalid)
    {
        [self _putFavoritesIntoPrefs];
    }

    // Update the Favorites menu.
    [self _updateFavoritesMenu];
}

- (void)_putFavoritesIntoPrefs
{
    NSMutableArray *favPrefList = [NSMutableArray array];
    int numFavs = [_favoritesList count];
    int i;

    // Update the UserDefaults.
    for (i = 0; i < numFavs; i++)
    {
        AKDocLocator *favItem = [_favoritesList objectAtIndex:i];

        [favPrefList addObject:[favItem asPrefDictionary]];
    }
    [AKPrefUtils
        setArrayValue:favPrefList
        forPref:AKFavoritesPrefName];

    // Update the Favorites menu.
    [self _updateFavoritesMenu];
}

- (void)_updateFavoritesMenu
{
    NSMenu *mainMenu = [NSApp mainMenu];
    NSMenu *favoritesMenu =
        [[mainMenu itemWithTitle:@"Favorites"] submenu];
    int numFavs = [_favoritesList count];
    int i;

    while ([favoritesMenu numberOfItems] > 2)
    {
        [favoritesMenu removeItemAtIndex:2];
    }

    for (i = 0; i < numFavs; i++)
    {
        AKDocLocator *favItem = [_favoritesList objectAtIndex:i];
        NSMenuItem *menuItem =
            [[[NSMenuItem alloc]
                initWithTitle:[favItem stringToDisplayInLists]
                action:@selector(jumpToDocLocatorRepresentedBy:)
                keyEquivalent:@""] autorelease];

        if (i < 9)
        {
            [menuItem setKeyEquivalent:
                [NSString stringWithFormat:@"%d", (i + 1)]];
            [menuItem setKeyEquivalentModifierMask:NSControlKeyMask];
        }

        [menuItem setRepresentedObject:favItem];
        [favoritesMenu addItem:menuItem];
    }
}

@end
