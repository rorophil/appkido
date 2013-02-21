/*
 * AKDocParser.h
 *
 * Created by Andy Lee on Mon Jul 08 2002.
 * Copyright (c) 2003, 2004 Andy Lee. All rights reserved.
 */

#import "AKParser.h"

@class AKFileSection;

/*
 * Base class for parsers that parse HTML documentation files.
 *
 * Uses parse results to create and/or modify database nodes.
 *
 * Subclasses parse specific types of doc files and instantiate different kinds
 * of AKDatabaseNode, depending on what the files contain.
 *
 * Doc files have a three-level hierarchical structure, which is reflected in a
 * tree of AKFileSections that gets constructed during parsing.  There is a
 * <b>root section</b>, whose child sections are called <b>major sections</b>.
 * The child sections of a major section are called <b>minor sections</b>.
 *
 * In general, the root section corresponds to a topic (see AKTopic), the major
 * sections to subtopics within the topic (see AKSubtopic), and the minor
 * sections to docs within a subtopic (see AKDoc).  In some cases, when we are
 * done parsing, we promote a minor section to a major section, so things get
 * grouped more logically for our purposes (see AKCocoaBehaviorDocParser).
 */
// [agl] illustrate thus:
//  <h1>TopicName</h1>       <-->  root section
//    <h2>SubtopicName</h2>  <-->    major section
//      <h3>DocName</h3>     <-->      minor section
// ...except the subordinate tags might not be <h2> and <h3>.  They are
// in Jaguar, but in Panther they are (I think) <h2> and <h4>, and in Tiger,
// they are <h2> and <div class="mach4">.
//
// DocName might contain extraneous whitespace (including
// leading/trailing and newlines) and/or HTML character constants.  It's
// too expensive to de-HTMLize during doc parsing ([agl] or is it? think about
// this); so we defer de-HTMLizing to when we display the doc name.
@interface AKDocParser : AKParser
{
@private
    // Used during parsing.  Doc files have a hierarchical structure.
    // This stack keeps track of our current path down the hierarchy.
    NSMutableArray *_sectionStack;

@protected
    // Value is assigned after a successful parse.
    AKFileSection *_rootSectionOfCurrentFile;

    // Contains the most recently parsed token.
    char _token[AKParserTokenBufferSize];
}


#pragma mark -
#pragma mark Parsing

/*!
 * Consumes a token from the input stream and puts it into _token. On exit,
 * _current points just after the token.
 *
 * All non-alphanumeric, non-whitespace characters are considered punctuation
 * and are treated as individual tokens.
 */
- (BOOL)parseToken;

/*!
 * Calls -parseToken one or more times. Skips over tokens that are HTML markup
 * (tags, character entities, etc.) and consumes the next non-markup token in
 * the input stream. Puts that token in _token. On exit, _current points just
 * after the token.
 */
- (BOOL)parseNonMarkupToken;


#pragma mark -
#pragma mark Using parse results

/*!
 * Returns the root of the file section hierarchy for the file most recently
 * parsed by the receiver.
 */
- (AKFileSection *)rootSectionOfCurrentFile;

/*! Called after each file is parsed. Does nothing by default. */
- (void)applyParseResults;


#pragma mark -
#pragma mark Heinous kludge

// [agl] wish I didn't have to do this -- curse you, Apple!  someday I
// should write a smarter higher-level parser; problem is, in Tiger
// they stopped using <h#> tags to demarcate method docs -- they use
// <div class="mach4">methodName</div>; here I replace the div's with
// h3's -- but I have to do so without moving anything around, because
// byte locations will be located during parsing, and those byte locations
// have to be correct in the original, unkludged data
//
// [agl] had to add another kludge to convert <span> tags to <h1> tags
// so the Functions and TypesAndConstants pages get parsed properly.
+ (NSMutableData *)kludgeHTMLForTiger:(NSData *)sourceData;


@end
