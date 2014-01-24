//
//  SyncViewController.m
//  AlfrescoApp
//
//  Created by Mohamad Saeedi on 30/09/2013.
//  Copyright (c) 2013 Alfresco. All rights reserved.
//

#import "SyncViewController.h"
#import "SyncManager.h"
#import "SyncCell.h"
#import "Utility.h"
#import "PreviewViewController.h"
#import "MetaDataViewController.h"
#import "UniversalDevice.h"
#import "SyncObstaclesViewController.h"
#import "FailedTransferDetailViewController.h"
#import "AccountManager.h"
#import "UserAccount.h"
#import "ThumbnailManager.h"
#import "Constants.h"

static NSInteger const kCellHeight = 84;
static CGFloat const kFooterHeight = 32.0f;
static CGFloat const kCellImageViewWidth = 32.0f;
static CGFloat const kCellImageViewHeight = 32.0f;

@interface SyncViewController ()

@property (nonatomic) AlfrescoNode *parentNode;
@property (nonatomic, strong) AlfrescoDocumentFolderService *documentFolderService;
@property (nonatomic, strong) UIPopoverController *retrySyncPopover;
@property (nonatomic, strong) AlfrescoNode *retrySyncNode;
@property (nonatomic, strong) UILabel *tableViewFooter;
@property (nonatomic, assign) BOOL didSyncAfterSessionRefresh;
@end

@implementation SyncViewController

- (id)initWithParentNode:(AlfrescoNode *)node andSession:(id<AlfrescoSession>)session
{
    self = [super initWithNibName:NSStringFromClass([self class]) andSession:session];
    if (self)
    {
        self.session = session;
        self.parentNode = node;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    if (!self.didSyncAfterSessionRefresh || self.parentNode != nil)
    {
        self.documentFolderService = [[AlfrescoDocumentFolderService alloc] initWithSession:self.session];
        [self loadSyncNodesForFolder:self.parentNode];
    }
    
    if (self.parentNode != nil)
    {
        [self disablePullToRefresh];
    }
    
    self.title = self.parentNode ? self.parentNode.name : NSLocalizedString(@"Favorites", @"Favorites Title");
    self.tableViewFooter = [[UILabel alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(selectedAccountChanged:)
                                                 name:kAlfrescoSelectedAccountChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusChanged:)
                                                 name:kSyncStatusChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSyncObstacles:)
                                                 name:kSyncObstaclesNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didAddNodeToFavourites:)
                                                 name:kFavouritesDidAddNodeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didRemoveNodeFromFavourites:)
                                                 name:kFavouritesDidRemoveNodeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Private Methods

- (void)loadSyncNodesForFolder:(AlfrescoNode *)folder
{
    if (folder)
    {
        self.tableViewData = [[SyncManager sharedManager] topLevelSyncNodesOrNodesInFolder:(AlfrescoFolder *)self.parentNode];
    }
    else
    {
        self.tableViewData = [[SyncManager sharedManager] syncDocumentsAndFoldersForSession:self.session withCompletionBlock:^(NSMutableArray *syncedNodes) {
            if (syncedNodes)
            {
                self.tableViewData = syncedNodes;
                [self.tableView reloadData];
                [self hidePullToRefreshView];
            }
        }];
    }
    [self hidePullToRefreshView];
    [self.tableView reloadData];
}

- (void)selectedAccountChanged:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    id session = [userInfo objectForKey:kAlfrescoSelectedAccountSession];
    self.session = (session == [NSNull null]) ? nil :  session;
    
    [self.navigationController popToRootViewControllerAnimated:YES];
    if (![[SyncManager sharedManager] isFirstUse])
    {
        self.documentFolderService = [[AlfrescoDocumentFolderService alloc] initWithSession:self.session];
        [self loadSyncNodesForFolder:self.parentNode];
        self.didSyncAfterSessionRefresh = YES;
    }
}

- (void)didAddNodeToFavourites:(NSNotification *)notification
{
    AlfrescoNode *nodeAdded = (AlfrescoNode *)notification.object;
    [self addAlfrescoNodes:@[nodeAdded] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)didRemoveNodeFromFavourites:(NSNotification *)notification
{
    AlfrescoNode *nodeRemoved = (AlfrescoNode *)notification.object;
    NSIndexPath *index = [self indexPathForNodeWithIdentifier:nodeRemoved.identifier inNodeIdentifiers:[self.tableViewData valueForKey:@"identifier"]];
    [self.tableViewData removeObjectAtIndex:index.row];
    [self.tableView deleteRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - TableView Datasource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.tableViewData.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return kCellHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return kFooterHeight;
}

-(UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    self.tableViewFooter.text = [self tableView:tableView titleForFooterInSection:section];
    self.tableViewFooter.backgroundColor = [UIColor whiteColor];
    self.tableViewFooter.textAlignment = NSTextAlignmentCenter;
    
    return self.tableViewFooter;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    //static NSString *cellIdentifier = kSyncTableCellIdentifier;
    SyncCell *syncCell = [tableView dequeueReusableCellWithIdentifier:kSyncTableCellIdentifier];
    if (nil == syncCell)
    {
        NSArray *subViews = [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([SyncCell class]) owner:self options:nil];
        if (subViews.count > 0)
        {
            syncCell = (SyncCell *)[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([SyncCell class]) owner:self options:nil][0];
            
            static NSInteger const infoIconRightMargin = 5;
            static NSInteger const infoIconTopMargin = 5;
            static NSInteger const infoIconFrameWidth = 16;
            static NSInteger const infoIconFrameHeight = 16;
            
            int infoIconsCurrentXPosition = self.tableView.frame.size.width - infoIconFrameWidth - infoIconRightMargin;
            syncCell.status = [[UIImageView alloc] initWithFrame:CGRectMake(infoIconsCurrentXPosition, infoIconTopMargin, infoIconFrameWidth, infoIconFrameHeight)];
            [syncCell addSubview:syncCell.status];
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:syncCell
                                             selector:@selector(statusChanged:)
                                                 name:kSyncStatusChangeNotification
                                               object:nil];
    
    SyncManager *syncManager = [SyncManager sharedManager];
    
    AlfrescoNode *node = self.tableViewData[indexPath.row];
    SyncNodeStatus *nodeStatus = [syncManager syncStatusForNodeWithId:node.identifier];
    
    syncCell.node = node;
    syncCell.filename.text = node.name;
    
    if (node.isFolder)
    {
        syncCell.image.image = imageForType(@"folder");
    }
    else if (node.isDocument)
    {
        AlfrescoDocument *document = (AlfrescoDocument *)node;
        ThumbnailManager *thumbnailManager = [ThumbnailManager sharedManager];
        UIImage *thumbnail = [thumbnailManager thumbnailFromDiskForDocument:document];
        
        if (!thumbnail)
        {
            thumbnail = [thumbnailManager thumbnailForNode:document withParentNode:self.parentNode session:self.session completionBlock:^(NSString *savedFileName, NSError *error) {
                
                [syncCell.image setImageAtPath:savedFileName withFade:YES];
            }];
        }
        syncCell.image.image = thumbnail;
    }
    
    [syncCell updateFavoriteState:nodeStatus.isFavorite];
    
    [syncCell updateNodeDetails:nodeStatus];
    [syncCell updateCellWithNodeStatus:nodeStatus propertyChanged:kSyncStatus];
    
    return syncCell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SyncManager *syncManager = [SyncManager sharedManager];
    AlfrescoNode *selectedNode = self.tableViewData[indexPath.row];
    SyncNodeStatus *nodeStatus = [syncManager syncStatusForNodeWithId:selectedNode.identifier];
    
    if (selectedNode.isFolder)
    {
        SyncViewController *controller = [[SyncViewController alloc] initWithParentNode:selectedNode andSession:self.session];
        [self.navigationController pushViewController:controller animated:YES];
    }
    else
    {
        NSString *filePath = [syncManager contentPathForNode:(AlfrescoDocument *)selectedNode];
        if (filePath)
        {
            PreviewViewController *previewController = [[PreviewViewController alloc] initWithDocument:(AlfrescoDocument *)selectedNode documentPermissions:nil contentFilePath:filePath session:self.session displayOverlayCloseButton:NO];
            [UniversalDevice pushToDisplayViewController:previewController usingNavigationController:self.navigationController animated:YES];
        }
        else
        {
            if (nodeStatus.status == SyncStatusLoading)
            {
                [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }
            NSString *downloadDestinationPath = [[[AlfrescoFileManager sharedManager] temporaryDirectory] stringByAppendingPathComponent:selectedNode.name];
            NSOutputStream *outputStream = [[AlfrescoFileManager sharedManager] outputStreamToFileAtPath:downloadDestinationPath append:NO];
            
            [self showHUD];
            [self.documentFolderService retrievePermissionsOfNode:selectedNode completionBlock:^(AlfrescoPermissions *permissions, NSError *error) {
                [self.documentFolderService retrieveContentOfDocument:(AlfrescoDocument *)selectedNode outputStream:outputStream completionBlock:^(BOOL succeeded, NSError *error) {
                    [self hideHUD];
                    if (succeeded)
                    {
                        PreviewViewController *previewController = [[PreviewViewController alloc] initWithDocument:(AlfrescoDocument *)selectedNode documentPermissions:permissions contentFilePath:downloadDestinationPath session:self.session displayOverlayCloseButton:NO];
                        [UniversalDevice pushToDisplayViewController:previewController usingNavigationController:self.navigationController animated:YES];
                    }
                    else
                    {
                        // display an error
                        displayErrorMessage([NSString stringWithFormat:NSLocalizedString(@"error.filefolder.content.failedtodownload", @"Failed to download the file"), [ErrorDescriptions descriptionForError:error]]);
                        [Notifier notifyWithAlfrescoError:error];
                    }
                } progressBlock:^(unsigned long long bytesTransferred, unsigned long long bytesTotal) {
                    // progress indicator update
                }];
            }];
        }
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    SyncManager *syncManager = [SyncManager sharedManager];
    AlfrescoNode *node = self.tableViewData[indexPath.row];
    SyncNodeStatus *nodeStatus = [syncManager syncStatusForNodeWithId:node.identifier];
    
    switch (nodeStatus.status)
    {
        case SyncStatusLoading:
            [syncManager cancelSyncForDocument:(AlfrescoDocument *)node];
            break;
            
        case SyncStatusFailed:
        {
            self.retrySyncNode = node;
            [self showPopoverForFailedSyncNodeAtIndexPath:indexPath];
            break;
        }
            
        default:
        {
            MetaDataViewController *metaDataViewController = [[MetaDataViewController alloc] initWithAlfrescoNode:node session:self.session];
            [UniversalDevice pushToDisplayViewController:metaDataViewController usingNavigationController:self.navigationController animated:YES];
            break;
        }
    }
}

- (void)showPopoverForFailedSyncNodeAtIndexPath:(NSIndexPath *)indexPath
{
    SyncManager *syncManager = [SyncManager sharedManager];
    AlfrescoNode *node = self.tableViewData[indexPath.row];
    NSString *errorDescription = [syncManager syncErrorDescriptionForNode:node];
    
    if (IS_IPAD)
    {
        FailedTransferDetailViewController *syncFailedDetailController = nil;
        
        syncFailedDetailController = [[FailedTransferDetailViewController alloc] initWithTitle:NSLocalizedString(@"sync.state.failed-to-sync", @"Upload failed popover title")
                                                                                       message:errorDescription retryCompletionBlock:^(BOOL retry) {
                                                                                           if (retry)
                                                                                           {
                                                                                               [self retrySyncAndCloseRetryPopover];
                                                                                           }
                                                                                       }];
        
        self.retrySyncPopover = [[UIPopoverController alloc] initWithContentViewController:syncFailedDetailController];
        [self.retrySyncPopover setPopoverContentSize:syncFailedDetailController.view.frame.size];
        
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
        if(cell.accessoryView.window != nil)
        {
            [self.retrySyncPopover presentPopoverFromRect:cell.accessoryView.frame inView:cell permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        }
    }
    else
    {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"sync.state.failed-to-sync", @"Upload Failed")
                                    message:errorDescription
                                   delegate:self
                          cancelButtonTitle:NSLocalizedString(@"Close", @"Close")
                          otherButtonTitles:NSLocalizedString(@"Retry", @"Retry"), nil] show];
    }
}

- (void)retrySyncAndCloseRetryPopover
{
    [[SyncManager sharedManager] retrySyncForDocument:(AlfrescoDocument *)self.retrySyncNode];
    [self.retrySyncPopover dismissPopoverAnimated:YES];
    self.retrySyncNode = nil;
    self.retrySyncPopover = nil;
}

#pragma mark - UIRefreshControl Functions

- (void)refreshTableView:(UIRefreshControl *)refreshControl
{
    [self showLoadingTextInRefreshControl:refreshControl];
    [self loadSyncNodesForFolder:self.parentNode];
}

#pragma mark - Status Changed Notification Handling

- (void)statusChanged:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    
    NSString *propertyChanged = [info objectForKey:kSyncStatusPropertyChangedKey];
    NSString *notificationNodeId = [info objectForKey:kSyncStatusNodeIdKey];
    
    if ([propertyChanged isEqualToString:kSyncTotalSize])
    {
        if (!self.parentNode || [self.parentNode.identifier isEqualToString:notificationNodeId])
        {
            self.tableViewFooter.text = [self tableFooterText];
        }
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return [self tableFooterText];
}

#pragma mark - Private Class Functions

- (void)handleSyncObstacles:(NSNotification *)notification
{
    NSMutableDictionary *syncObstacles = [[notification.userInfo objectForKey:kSyncObstaclesKey] mutableCopy];
    
    if (syncObstacles)
    {
        SyncObstaclesViewController *syncObstaclesController = [[SyncObstaclesViewController alloc] initWithErrors:syncObstacles];
        syncObstaclesController.modalPresentationStyle = UIModalPresentationFormSheet;
        
        UINavigationController *syncObstaclesNavigationController = [[UINavigationController alloc] initWithRootViewController:syncObstaclesController];
        [UniversalDevice displayModalViewController:syncObstaclesNavigationController onController:self withCompletionBlock:nil];
    }
}

- (NSString *)tableFooterText
{
    SyncNodeStatus *nodeStatus = nil;
    if (!self.parentNode)
    {
        NSString *selectedAccountIdentifier = [[[AccountManager sharedManager] selectedAccount] accountIdentifier];
        nodeStatus = [[SyncManager sharedManager] syncStatusForNodeWithId:selectedAccountIdentifier];
    }
    else
    {
        nodeStatus = [[SyncManager sharedManager] syncStatusForNodeWithId:self.parentNode.identifier];
    }
    
    NSString *footerText = @"";
    
    if (self.tableViewData.count > 0)
    {
        NSString *documentsText = @"";
        
        switch (self.tableViewData.count)
        {
            case 1:
            {
                documentsText = NSLocalizedString(@"downloadview.footer.one-document", @"1 Document");
                break;
            }
            default:
            {
                documentsText = [NSString stringWithFormat:NSLocalizedString(@"downloadview.footer.multiple-documents", @"%d Documents"), self.tableViewData.count];
                break;
            }
        }
        
        footerText = [NSString stringWithFormat:@"%@ %@", documentsText, stringForLongFileSize(nodeStatus.totalSize)];
    }
    return footerText;
}

#pragma mark UIAlertView delegate methods

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex)
    {
        [[SyncManager sharedManager] retrySyncForDocument:(AlfrescoDocument *)self.retrySyncNode];
        self.retrySyncNode = nil;
    }
}

@end
