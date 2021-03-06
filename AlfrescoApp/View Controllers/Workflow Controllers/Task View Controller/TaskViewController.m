/*******************************************************************************
 * Copyright (C) 2005-2014 Alfresco Software Limited.
 * 
 * This file is part of the Alfresco Mobile iOS App.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *  
 *  http://www.apache.org/licenses/LICENSE-2.0
 * 
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 ******************************************************************************/
 
#import "TaskViewController.h"
#import "LoginManager.h"
#import "AccountManager.h"
#import "TasksCell.h"
#import "TaskGroupItem.h"
#import "TaskDetailsViewController.h"
#import "UniversalDevice.h"
#import "TaskTypeViewController.h"

static NSString * const kDateFormat = @"dd MMMM yyyy";
static NSString * const kActivitiReview = @"activitiReview";
static NSString * const kActivitiParallelReview = @"activitiParallelReview";
static NSString * const kActivitiToDo = @"activitiAdhoc";
static NSString * const kActivitiInviteNominated = @"activitiInvitationNominated";
static NSString * const kJBPMReview = @"wf:review";
static NSString * const kJBPMParallelReview = @"wf:parallelreview";
static NSString * const kJBPMToDo = @"wf:adhoc";
static NSString * const kJBPMInviteNominated = @"wf:invitationNominated";
static NSString * const kSupportedTasksPredicateFormat = @"processDefinitionIdentifier CONTAINS %@ AND NOT (processDefinitionIdentifier CONTAINS[c] 'pooled')";
static NSString * const kAdhocProcessTypePredicateFormat = @"SELF CONTAINS[cd] %@";
static NSString * const kInitiatorWorkflowsPredicateFormat = @"initiatorUsername like %@";

static NSString * const kTaskCellIdentifier = @"TaskCell";

@interface TaskViewController () <UIActionSheetDelegate>

@property (nonatomic, strong) AlfrescoWorkflowService *workflowService;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSPredicate *supportedTasksPredicate;
@property (nonatomic, strong) NSPredicate *adhocProcessTypePredicate;
@property (nonatomic, strong) NSPredicate *inviteProcessTypePredicate;
@property (nonatomic, assign) TaskFilter displayedTaskFilter;
@property (nonatomic, strong) TaskGroupItem *myTasks;
@property (nonatomic, strong) TaskGroupItem *tasksIStarted;
@property (nonatomic, weak) UIBarButtonItem *filterButton;

@end

@implementation TaskViewController

- (id)initWithSession:(id<AlfrescoSession>)session
{
    self = [super initWithNibName:NSStringFromClass(self.class) andSession:session];
    if (self)
    {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:kDateFormat];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskListDidChange:) name:kAlfrescoWorkflowTaskListDidChangeNotification object:nil];
        [self createWorkflowServicesWithSession:session];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"tasks.title", @"Tasks Title");
    self.tableView.emptyMessage = NSLocalizedString(@"tasks.empty", @"No Tasks");
    
    UIBarButtonItem *filterButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"tasks.view.button", @"View") style:UIBarButtonItemStylePlain target:self action:@selector(displayActionSheet:event:)];
    self.filterButton = filterButton;
    
    UIBarButtonItem *addTaskButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createTask:)];

    if (IS_IPAD)
    {
        self.navigationItem.rightBarButtonItem = addTaskButton;
        self.navigationItem.leftBarButtonItem = filterButton;
    }
    else
    {
        self.navigationItem.rightBarButtonItems = @[filterButton, addTaskButton];
    }

    UINib *cellNib = [UINib nibWithNibName:@"TasksCell" bundle:nil];
    [self.tableView registerNib:cellNib forCellReuseIdentifier:kTaskCellIdentifier];
    
    if (self.session)
    {
        [self showHUD];
        [self loadTasksForTaskFilter:self.displayedTaskFilter listingContext:nil forceRefresh:YES completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
            [self hideHUD];
            [self reloadTableViewWithPagingResult:pagingResult error:error];
        }];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)createTask:(id)sender
{
    TaskTypeViewController *taskTypeController = [[TaskTypeViewController alloc] initWithSession:self.session];
    UINavigationController *newTaskNavigationController = [[UINavigationController alloc] initWithRootViewController:taskTypeController];
    newTaskNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:newTaskNavigationController animated:YES completion:nil];
}

#pragma mark - Private Functions

- (void)sessionReceived:(NSNotification *)notification
{
    id <AlfrescoSession> session = notification.object;
    self.session = session;
    
    if (self.session)
    {
        [self createWorkflowServicesWithSession:session];
        [self.myTasks clearAllTasks];
        [self.tasksIStarted clearAllTasks];
        
        if ([self shouldRefresh])
        {
            [self loadTasksForTaskFilter:TaskFilterTask listingContext:nil forceRefresh:YES completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
                [self hideHUD];
                [self hidePullToRefreshView];
                [self reloadTableViewWithPagingResult:pagingResult error:error];
            }];
        }
    }
}

- (void)taskListDidChange:(NSNotification *)notification
{
    [self reloadDataForAllTaskFilters];
}

- (void)reloadDataForAllTaskFilters
{
    // reload tasks and workflows following completion
    __weak typeof(self) weakSelf = self;

    [self showHUD];
    AlfrescoListingContext *tasksListingContext = [[AlfrescoListingContext alloc] initWithMaxItems:[@(self.myTasks.tasksBeforeFiltering.count) intValue] skipCount:0];
    [self loadTasksWithListingContext:tasksListingContext completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
        [weakSelf hideHUD];
        if (pagingResult)
        {
            [weakSelf.myTasks clearAllTasks];
            [weakSelf.myTasks addAndApplyFilteringToTasks:pagingResult.objects];
            
            // currently being displayed, refresh the tableview.
            if (weakSelf.displayedTaskFilter == TaskFilterTask)
            {
                weakSelf.tableViewData = [weakSelf.myTasks.tasksAfterFiltering mutableCopy];
                [weakSelf.tableView reloadData];
            }
        }
    }];
    
    AlfrescoListingContext *workflowListingContext = [[AlfrescoListingContext alloc] initWithMaxItems:[@(self.tasksIStarted.tasksBeforeFiltering.count) intValue] skipCount:0];
    [self loadWorkflowProcessesWithListingContext:workflowListingContext completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
        [weakSelf hideHUD];
        if (pagingResult)
        {
            [weakSelf.tasksIStarted clearAllTasks];
            [weakSelf.tasksIStarted addAndApplyFilteringToTasks:pagingResult.objects];
            
            // currently being displayed, refresh the tableview.
            if (weakSelf.displayedTaskFilter == TaskFilterProcess)
            {
                weakSelf.tableViewData = [weakSelf.tasksIStarted.tasksAfterFiltering mutableCopy];
                [weakSelf.tableView reloadData];
            }
        }
    }];
}

- (void)createWorkflowServicesWithSession:(id<AlfrescoSession>)session
{
    self.workflowService = [[AlfrescoWorkflowService alloc] initWithSession:session];

    if (!self.supportedTasksPredicate)
    {
        NSArray *supportedProcessIdentifiers = @[kActivitiReview, kActivitiParallelReview, kActivitiInviteNominated, kActivitiToDo, kJBPMReview, kJBPMParallelReview, kJBPMToDo, kJBPMInviteNominated];
        NSMutableArray *tasksSubpredicates = [[NSMutableArray alloc] init];
        [supportedProcessIdentifiers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [tasksSubpredicates addObject:[NSPredicate predicateWithFormat:kSupportedTasksPredicateFormat, obj]];
        }];
        
        self.supportedTasksPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:tasksSubpredicates];
    }
    
    if (!self.adhocProcessTypePredicate)
    {
        NSArray *supportedProcessIdentifiers = @[kActivitiToDo, kJBPMToDo];
        NSMutableArray *tasksSubpredicates = [[NSMutableArray alloc] init];
        [supportedProcessIdentifiers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [tasksSubpredicates addObject:[NSPredicate predicateWithFormat:kAdhocProcessTypePredicateFormat, obj]];
        }];
        
        self.adhocProcessTypePredicate = [NSCompoundPredicate orPredicateWithSubpredicates:tasksSubpredicates];
    }
    
    if (!self.inviteProcessTypePredicate)
    {
        NSArray *supportedProcessIdentifiers = @[kActivitiInviteNominated, kJBPMInviteNominated];
        NSMutableArray *tasksSubpredicates = [[NSMutableArray alloc] init];
        [supportedProcessIdentifiers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [tasksSubpredicates addObject:[NSPredicate predicateWithFormat:kAdhocProcessTypePredicateFormat, obj]];
        }];
        
        self.inviteProcessTypePredicate = [NSCompoundPredicate orPredicateWithSubpredicates:tasksSubpredicates];
    }
    
    NSPredicate *initiatorSubpredicate = [NSPredicate predicateWithFormat:kInitiatorWorkflowsPredicateFormat, self.session.personIdentifier];
    NSPredicate *tasksIStartedPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[self.supportedTasksPredicate, initiatorSubpredicate]];

    self.myTasks = [[TaskGroupItem alloc] initWithTitle:NSLocalizedString(@"tasks.title.mytasks", @"My Tasks Title") filteringPredicate:self.supportedTasksPredicate];
    self.tasksIStarted = [[TaskGroupItem alloc] initWithTitle:NSLocalizedString(@"tasks.title.taskistarted", @"Tasks I Started Title") filteringPredicate:tasksIStartedPredicate];
}

- (TaskGroupItem *)taskGroupItemForType:(TaskFilter)taskType
{
    TaskGroupItem *returnGroupItem = nil;
    switch (taskType)
    {
        case TaskFilterTask:
            returnGroupItem = self.myTasks;
            break;

        case TaskFilterProcess:
            returnGroupItem = self.tasksIStarted;
            break;
    }
    return returnGroupItem;
}

- (void)loadTasksForTaskFilter:(TaskFilter)taskFilter listingContext:(AlfrescoListingContext *)listingContext forceRefresh:(BOOL)forceRefresh completionBlock:(AlfrescoPagingResultCompletionBlock)completionBlock
{
    TaskGroupItem *groupToSwitchTo = [self taskGroupItemForType:taskFilter];
    
    self.displayedTaskFilter = taskFilter;
    self.title = groupToSwitchTo.title;
    
    if (groupToSwitchTo.hasDisplayableTasks == NO || forceRefresh || groupToSwitchTo.hasMoreItems)
    {
        if (forceRefresh)
        {
            listingContext = nil;
            [groupToSwitchTo clearAllTasks];
        }
        
        switch (taskFilter)
        {
            case TaskFilterTask:
            {
                [self loadTasksWithListingContext:listingContext completionBlock:completionBlock];
            }
            break;
                
            case TaskFilterProcess:
            {
                [self loadWorkflowProcessesWithListingContext:listingContext completionBlock:completionBlock];
            }
            break;
        }
    }
    else
    {
        self.tableViewData = [groupToSwitchTo.tasksAfterFiltering mutableCopy];
        [self.tableView reloadData];
    }
}

- (void)loadWorkflowProcessesWithListingContext:(AlfrescoListingContext *)listingContext completionBlock:(void (^)(AlfrescoPagingResult *pagingResult, NSError *error))completionBlock
{
    if (!listingContext)
    {
        listingContext = self.defaultListingContext;
    }
    
    // create a new listing context so we can filter the processes
    AlfrescoListingFilter *filter = [[AlfrescoListingFilter alloc] initWithFilter:kAlfrescoFilterByWorkflowStatus value:kAlfrescoFilterValueWorkflowStatusActive];
    AlfrescoListingContext *filteredListingContext = [[AlfrescoListingContext alloc] initWithMaxItems:listingContext.maxItems
                                                                                            skipCount:listingContext.skipCount
                                                                                         sortProperty:listingContext.sortProperty
                                                                                        sortAscending:listingContext.sortAscending
                                                                                        listingFilter:filter];
    
    [self.workflowService retrieveProcessesWithListingContext:filteredListingContext completionBlock:completionBlock];
}

- (void)loadTasksWithListingContext:(AlfrescoListingContext *)listingContext completionBlock:(void (^)(AlfrescoPagingResult *pagingResult, NSError *error))completionBlock
{
    [self.workflowService retrieveTasksWithListingContext:(listingContext ?: self.defaultListingContext) completionBlock:completionBlock];
}

- (void)displayActionSheet:(id)sender event:(UIEvent *)event
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    
    [actionSheet addButtonWithTitle:NSLocalizedString(@"tasks.title.mytasks", @"My Tasks Title")];
    [actionSheet addButtonWithTitle:NSLocalizedString(@"tasks.title.taskistarted", @"Tasks I Started Title")];
    [actionSheet setCancelButtonIndex:[actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel")]];
    
    if (IS_IPAD)
    {
        [actionSheet showFromBarButtonItem:sender animated:YES];
    }
    else
    {
        [actionSheet showInView:self.view];
    }
    
    // UIActionSheet button titles don't pick up the global tint color by default
    [Utility colorButtonsForActionSheet:actionSheet tintColor:[UIColor appTintColor]];

    self.filterButton.enabled = NO;
}

#pragma mark - Overridden Functions

- (void)reloadTableViewWithPagingResult:(AlfrescoPagingResult *)pagingResult error:(NSError *)error
{
    if (pagingResult)
    {
        switch (self.displayedTaskFilter)
        {
            case TaskFilterTask:
            {
                [self.myTasks clearAllTasks];
                [self.myTasks addAndApplyFilteringToTasks:pagingResult.objects];
                self.myTasks.hasMoreItems = pagingResult.hasMoreItems;
                self.tableViewData = [self.myTasks.tasksAfterFiltering mutableCopy];
            }
            break;
                
            case TaskFilterProcess:
            {
                [self.tasksIStarted clearAllTasks];
                [self.tasksIStarted addAndApplyFilteringToTasks:pagingResult.objects];
                self.tasksIStarted.hasMoreItems = pagingResult.hasMoreItems;
                self.tableViewData = [self.tasksIStarted.tasksAfterFiltering mutableCopy];
            }
            break;
        }
        
        [self.tableView reloadData];
    }
}

- (void)addMoreToTableViewWithPagingResult:(AlfrescoPagingResult *)pagingResult error:(NSError *)error
{
    if (pagingResult)
    {
        TaskGroupItem *currentGroupedItem = [self taskGroupItemForType:self.displayedTaskFilter];
        [currentGroupedItem addAndApplyFilteringToTasks:pagingResult.objects];;
        currentGroupedItem.hasMoreItems = pagingResult.hasMoreItems;
        self.tableViewData = [currentGroupedItem.tasksAfterFiltering mutableCopy];
        [self.tableView reloadData];
    }
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.tableViewData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TasksCell *cell = [tableView dequeueReusableCellWithIdentifier:kTaskCellIdentifier];

    switch (self.displayedTaskFilter)
    {
        case TaskFilterTask:
        {
            AlfrescoWorkflowTask *currentTask = [self.tableViewData objectAtIndex:indexPath.row];
            cell.title = currentTask.summary;
            cell.dueDate = currentTask.dueAt;
            cell.priority = currentTask.priority;
            cell.processType = currentTask.name;
        }
        break;
            
        case TaskFilterProcess:
        {
            AlfrescoWorkflowProcess *currentProcess = [self.tableViewData objectAtIndex:indexPath.row];
            cell.title = currentProcess.summary;
            cell.dueDate = currentProcess.dueAt;
            cell.priority = currentProcess.priority;
            BOOL isAdhocProcessType = [self.adhocProcessTypePredicate evaluateWithObject:currentProcess.processDefinitionIdentifier];
            BOOL isInviteProcessType = [self.inviteProcessTypePredicate evaluateWithObject:currentProcess.processDefinitionIdentifier];
            
            NSString *processType = nil;
            if (isAdhocProcessType)
            {
                processType = NSLocalizedString(@"task.type.workflow.todo", @"Adhoc Process type");
            }
            else if (isInviteProcessType)
            {
                processType = NSLocalizedString(@"task.type.workflow.invitation", @"Invitation Process type");
            }
            else
            {
                processType = NSLocalizedString(@"task.type.workflow.review.and.approve", @"Review & Approve Process type");
            }
            cell.processType = processType;
        }
        break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    // the last row index of the table data
    TaskGroupItem *currentTaskGroup = [self taskGroupItemForType:self.displayedTaskFilter];
    
    NSUInteger lastRowIndex = currentTaskGroup.numberOfTasksAfterFiltering - 1;
    
    // if the last cell is about to be drawn, check if there are more sites
    if (indexPath.row == lastRowIndex)
    {
        AlfrescoListingContext *moreListingContext = [[AlfrescoListingContext alloc] initWithMaxItems:kMaxItemsPerListingRetrieve skipCount:[@(currentTaskGroup.numberOfTasksBeforeFiltering) intValue]];
        if ([currentTaskGroup hasMoreItems])
        {
            // show more items are loading ...
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [spinner startAnimating];
            self.tableView.tableFooterView = spinner;

            [self loadTasksForTaskFilter:self.displayedTaskFilter listingContext:moreListingContext forceRefresh:NO completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
                [self addMoreToTableViewWithPagingResult:pagingResult error:error];
                self.tableView.tableFooterView = nil;
            }];
        }
    }
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    id selectedObject = [self.tableViewData objectAtIndex:indexPath.row];
    
    TaskDetailsViewController *taskDetailsViewController = nil;
    
    if (self.displayedTaskFilter == TaskFilterTask)
    {
        // Sanity check
        if ([selectedObject isKindOfClass:[AlfrescoWorkflowTask class]])
        {
            taskDetailsViewController = [[TaskDetailsViewController alloc] initWithTask:(AlfrescoWorkflowTask *)selectedObject session:self.session];
        }
        else
        {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
        }
    }
    else if (self.displayedTaskFilter == TaskFilterProcess)
    {
        // Sanity check
        if ([selectedObject isKindOfClass:[AlfrescoWorkflowProcess class]])
        {
            taskDetailsViewController = [[TaskDetailsViewController alloc] initWithProcess:(AlfrescoWorkflowProcess *)selectedObject session:self.session];
        }
        else
        {
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
        }
    }
    
    [UniversalDevice pushToDisplayViewController:taskDetailsViewController usingNavigationController:self.navigationController animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TasksCell *cell = (TasksCell *)[self tableView:tableView cellForRowAtIndexPath:indexPath];
    [cell layoutIfNeeded];
    // "4.0f" hack value to resolve an issue between UILabel sizing and auto-layout
    return [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height + 4.0f;
}

#pragma mark - UIRefreshControl Functions

- (void)refreshTableView:(UIRefreshControl *)refreshControl
{
    [self showLoadingTextInRefreshControl:refreshControl];
    if (self.session)
    {
        [self loadTasksForTaskFilter:self.displayedTaskFilter listingContext:nil forceRefresh:YES completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
            [self reloadTableViewWithPagingResult:pagingResult error:error];
            [self hidePullToRefreshView];
        }];
    }
    else
    {
        [self hidePullToRefreshView];
        UserAccount *selectedAccount = [AccountManager sharedManager].selectedAccount;
        [[LoginManager sharedManager] attemptLoginToAccount:selectedAccount networkId:selectedAccount.selectedNetworkId completionBlock:^(BOOL successful, id<AlfrescoSession> alfrescoSession, NSError *error) {
            if (successful)
            {
                [self loadTasksForTaskFilter:self.displayedTaskFilter listingContext:nil forceRefresh:YES completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
                    [self reloadTableViewWithPagingResult:pagingResult error:error];
                }];
            }
        }];
    }
}

#pragma mark - UIActionSheetDelegate Functions

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *buttonTitle = [actionSheet buttonTitleAtIndex:buttonIndex];
    [actionSheet dismissWithClickedButtonIndex:0 animated:YES];
    self.filterButton.enabled = YES;
    
    if ([buttonTitle isEqualToString:NSLocalizedString(@"tasks.title.mytasks", @"My Tasks Title")])
    {
        [self loadTasksForTaskFilter:TaskFilterTask listingContext:nil forceRefresh:NO completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
            [self reloadTableViewWithPagingResult:pagingResult error:error];
        }];
    }
    else if ([buttonTitle isEqualToString:NSLocalizedString(@"tasks.title.taskistarted", @"Tasks I Started Title")])
    {
        [self loadTasksForTaskFilter:TaskFilterProcess listingContext:nil forceRefresh:NO completionBlock:^(AlfrescoPagingResult *pagingResult, NSError *error) {
            [self reloadTableViewWithPagingResult:pagingResult error:error];
        }];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex)
    {
        self.filterButton.enabled = YES;
    }
}

@end
