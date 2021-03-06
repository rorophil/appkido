/*
 * AKNotificationsSubtopic.m
 *
 * Created by Andy Lee on Wed Sep 25 2002.
 * Copyright (c) 2003, 2004 Andy Lee. All rights reserved.
 */

#import "AKNotificationsSubtopic.h"

#import "AKClassNode.h"
#import "AKNotificationDoc.h"

@implementation AKNotificationsSubtopic

#pragma mark -
#pragma mark AKSubtopic methods

- (NSString *)subtopicName
{
    return ([self includesAncestors]
            ? AKAllNotificationsSubtopicName
            : AKNotificationsSubtopicName);
}

- (NSString *)stringToDisplayInSubtopicList
{
    return ([self includesAncestors]
            ? [@"       " stringByAppendingString:[self subtopicName]]
            : [self subtopicName]);
}

#pragma mark -
#pragma mark AKMembersSubtopic methods

- (NSArray *)memberNodesForBehavior:(AKBehaviorNode *)behaviorNode
{
    if ([behaviorNode isClassNode])
    {
        return [(AKClassNode *)behaviorNode documentedNotifications];
    }
    else
    {
        return @[];
    }
}

+ (id)memberDocClass
{
    return [AKNotificationDoc class];
}

@end
