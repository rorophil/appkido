/*
 * AKGroupNodeSubtopic.m
 *
 * Created by Andy Lee on Sun Mar 28 2004.
 * Copyright (c) 2003, 2004 Andy Lee. All rights reserved.
 */

#import "AKGroupNodeSubtopic.h"

#import "AKGroupNode.h"

@implementation AKGroupNodeSubtopic

@synthesize groupNode = _groupNode;

#pragma mark -
#pragma mark Init/awake/dealloc

- (id)initWithGroupNode:(AKGroupNode *)groupNode
{
    if ((self = [super init]))
    {
        _groupNode = [groupNode retain];
    }

    return self;
}

- (id)init
{
    DIGSLogError_NondesignatedInitializer();
    return nil;
}

- (void)dealloc
{
    [_groupNode release];

    [super dealloc];
}

#pragma mark -
#pragma mark AKSubtopic methods

- (NSString *)subtopicName
{
    return [_groupNode nodeName];
}

@end
