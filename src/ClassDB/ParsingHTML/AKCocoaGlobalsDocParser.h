/*
 * AKCocoaGlobalsDocParser.h
 *
 * Created by Andy Lee on Tue May 17 2005.
 * Copyright (c) 2005 Andy Lee. All rights reserved.
 */

#import "AKDocParser.h"

/*
 * Parses an HTML file that documents a framework's data globals such as consts,
 * enums, typedefs, and global variables.
 */
@interface AKCocoaGlobalsDocParser : AKDocParser
{
@private
    // These ivars are only used during _parseNamesOfGlobalsInFileSection:.
    char _prevToken[AKParserTokenBufferSize];
    const char *_currTokenStart;
    const char *_currTokenEnd;
    const char *_prevTokenStart;
    const char *_prevTokenEnd;
}
@end
