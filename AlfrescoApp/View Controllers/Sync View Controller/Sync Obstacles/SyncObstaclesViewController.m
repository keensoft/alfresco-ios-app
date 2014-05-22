//
//  SyncObstaclesViewController.m
//  AlfrescoApp
//
//  Created by Mohamad Saeedi on 04/10/2013.
//  Copyright (c) 2013 Alfresco. All rights reserved.
//

#import "SyncObstaclesViewController.h"
#import "SyncManager.h"
#import "Utility.h"
#import "ThumbnailManager.h"

static NSInteger const kSectionDataIndex = 0;
static NSInteger const kSectionHeaderIndex = 1;

static CGFloat const kHeaderFontSize = 15.0f;

@interface SyncObstaclesViewController ()
@property (nonatomic, strong) NSMutableDictionary *errorDictionary;
@property (nonatomic, strong) NSMutableArray *sectionData;
@end

@implementation SyncObstaclesViewController

- (id)initWithErrors:(NSMutableDictionary *)errors
{
    self = [super init];
    if (self)
    {
        self.errorDictionary = errors;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if ([self respondsToSelector:@selector(edgesForExtendedLayout)])
    {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    UIBarButtonItem *dismissButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                   target:self
                                                                                   action:@selector(dismissModalView)];
    [self.navigationItem setRightBarButtonItem:dismissButton];
    
    [self.navigationItem setTitle:NSLocalizedString(@"sync-errors.title", @"Sync Error Navigation Bar Title")];
    
    NSMutableArray *syncDocumentsRemovedOnServer = self.errorDictionary[kDocumentsRemovedFromSyncOnServerWithLocalChanges];
    NSMutableArray *syncDocumentDeletedOnServer = self.errorDictionary[kDocumentsDeletedOnServerWithLocalChanges];
    
    self.sectionData = [NSMutableArray array];
    if (syncDocumentsRemovedOnServer.count > 0)
    {
        NSString *sectionHeader = @"sync-errors.unfavorited-on-server-with-local-changes.header";
        [self.sectionData addObject:@[syncDocumentsRemovedOnServer,sectionHeader]];
    }
    if (syncDocumentDeletedOnServer.count > 0)
    {
        NSString *sectionHeader = @"sync-errors.deleted-on-server-with-local-changes.header";
        [self.sectionData addObject:@[syncDocumentDeletedOnServer, sectionHeader]];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self handleSyncObstacles];
}

#pragma mark - Private Class functions

- (void)dismissModalView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)calculateHeaderHeightForSection:(NSInteger)section
{
    NSUInteger returnHeight = 0;
    
    if ([self.sectionData[section][kSectionDataIndex] count] != 0)
    {
        NSString *headerText = NSLocalizedString(self.sectionData[section][kSectionHeaderIndex], @"TableView Header Section Descriptions");
        CGRect rect = [headerText boundingRectWithSize:CGSizeMake(300, 2000)
                                               options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                                            attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:kHeaderFontSize]}
                                               context:nil];
        returnHeight = rect.size.height;
    }
    
    return returnHeight;
}

- (void)handleSyncObstacles
{
    NSArray *syncObstacles = [[self.errorDictionary objectForKey:kDocumentsDeletedOnServerWithLocalChanges] mutableCopy];
    for (AlfrescoDocument *document in syncObstacles)
    {
        [[SyncManager sharedManager] saveDeletedFileBeforeRemovingFromSync:document];
    }
}

- (void)reloadTableView
{
    NSInteger numberOfPopulatedErrorArrays = [self numberOfPopulatedErrorArrays];
    
    if (numberOfPopulatedErrorArrays == 0)
    {
        [self dismissModalView];
    }
    
    [self.tableView reloadData];
}

- (NSInteger)numberOfPopulatedErrorArrays
{
    int numberOfPopulatedErrorArrays = 0;
    
    for (NSMutableArray *data in self.sectionData)
    {
        if ([data[kSectionDataIndex] count] > 0)
        {
            numberOfPopulatedErrorArrays++;
        }
    }
    return numberOfPopulatedErrorArrays;
}

#pragma mark - UITableViewDataSourceDelegate functions

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self numberOfPopulatedErrorArrays];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.sectionData[section][kSectionDataIndex] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *standardCellIdentifier = @"StandardCellIdentifier";
    static NSString *syncErrorCellIdentifier = @"SyncObstacleCellIdentifier";
    
    AlfrescoDocument *document = self.sectionData[indexPath.section][kSectionDataIndex][indexPath.row];
    UITableViewCell *cell = nil;
    
    if ([self.sectionData[indexPath.section][kSectionHeaderIndex] isEqualToString:@"sync-errors.deleted-on-server-with-local-changes.header"])
    {
        UITableViewCell *standardCell = (UITableViewCell *)[tableView dequeueReusableCellWithIdentifier:standardCellIdentifier];
        if (!standardCell)
        {
            standardCell = (UITableViewCell *)[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:standardCellIdentifier];
            standardCell.imageView.contentMode = UIViewContentModeCenter;
        }
        standardCell.selectionStyle = UITableViewCellSelectionStyleNone;
        standardCell.textLabel.font = [UIFont systemFontOfSize:17.0f];
        standardCell.textLabel.text = document.name;
        cell = standardCell;
    }
    else
    {
        SyncObstacleTableViewCell *syncErrorCell = (SyncObstacleTableViewCell *)[tableView dequeueReusableCellWithIdentifier:syncErrorCellIdentifier];
        if (!syncErrorCell)
        {
            NSArray *nibItems = [[NSBundle mainBundle] loadNibNamed:@"SyncObstacleTableViewCell" owner:self options:nil];
            syncErrorCell = (SyncObstacleTableViewCell *)[nibItems objectAtIndex:0];
            syncErrorCell.delegate = self;
            [syncErrorCell.syncButton setTitle:NSLocalizedString(@"sync-errors.button.sync", @"Sync Button") forState:UIControlStateNormal];
            [syncErrorCell.saveButton setTitle:NSLocalizedString(@"sync-errors.button.save", @"Save Button") forState:UIControlStateNormal];
            NSAssert(nibItems, @"Failed to load object from NIB");
        }
        
        syncErrorCell.selectionStyle = UITableViewCellSelectionStyleNone;
        syncErrorCell.fileNameTextLabel.text = document.name;
        
        cell = syncErrorCell;
    }
    
    UIImage *thumbnail = [[ThumbnailManager sharedManager] thumbnailForDocument:document renditionType:kRenditionImageDocLib];
    if (thumbnail)
    {
        cell.imageView.image = thumbnail;
    }
    else
    {
        cell.imageView.image = smallImageForType([document.name pathExtension]);
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate Functions

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSArray *syncErrors = self.sectionData[section][kSectionDataIndex];
    if (syncErrors.count > 0)
    {
        int horizontalMargin = 10;
        CGFloat heightRequired = [self calculateHeaderHeightForSection:section];
        
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, heightRequired)];
        headerView.backgroundColor = [UIColor clearColor];
        headerView.contentMode = UIViewContentModeScaleAspectFit;
        headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(horizontalMargin, 0, tableView.frame.size.width - (horizontalMargin * 2), heightRequired)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        label.backgroundColor = [UIColor clearColor];
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.numberOfLines = 0;
        label.textColor = [UIColor colorWithRed:76.0/255.0 green:86.0/255.0 blue:108.0/255.0 alpha:1];
        label.font = [UIFont systemFontOfSize:kHeaderFontSize];
        
        label.text = NSLocalizedString(self.sectionData[section][kSectionHeaderIndex], @"TableView Header Section Descriptions");
        
        [headerView addSubview:label];
        return headerView;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return [self calculateHeaderHeightForSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.section == 0 && !IS_IPAD) ? 100.0f : 60.0f;
}

#pragma mark - SyncErrorTableViewDelegate Functions

- (NSIndexPath *)indexPathForButtonPressed:(UIButton *)button
{
    UIView *cell = button.superview;
    
    BOOL foundTableView = NO;
    while (!foundTableView)
    {
        if (![cell isKindOfClass:[UITableViewCell class]])
        {
            cell = (UITableViewCell *)cell.superview;
        }
        else
        {
            foundTableView = YES;
        }
    }
    
    NSIndexPath *cellIndexPath = [self.tableView indexPathForCell:(SyncObstacleTableViewCell *)cell];
    return cellIndexPath;
}
- (void)didPressSyncButton:(UIButton *)syncButton
{
    NSIndexPath *cellIndexPath = [self indexPathForButtonPressed:syncButton];
    NSArray *currentErrorArray = self.sectionData[cellIndexPath.section][kSectionDataIndex];
    AlfrescoDocument *document = currentErrorArray[cellIndexPath.row];
    [[SyncManager sharedManager] syncFileBeforeRemovingFromSync:document syncToServer:YES];
    [self reloadTableView];
}

- (void)didPressSaveToDownloadsButton:(UIButton *)saveButton
{
    NSIndexPath *cellIndexPath = [self indexPathForButtonPressed:saveButton];
    NSArray *currentErrorArray = self.sectionData[cellIndexPath.section][kSectionDataIndex];
    AlfrescoDocument *document = currentErrorArray[cellIndexPath.row];
    [[SyncManager sharedManager] syncFileBeforeRemovingFromSync:document syncToServer:NO];
    [self reloadTableView];
}

@end
