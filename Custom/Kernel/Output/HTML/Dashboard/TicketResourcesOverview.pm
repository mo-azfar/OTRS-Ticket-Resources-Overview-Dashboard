# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# Copyright (C) 2023 mo-azfar, https://github.com/mo-azfar
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::Dashboard::TicketResourcesOverview;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw( Config Name UserID )) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    $Self->{PrefKey}  = 'UserDashboardPref' . $Self->{Name} . '-Shown';
    $Self->{CacheKey} = $Self->{Name} . '-' . $Self->{UserID};

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    return;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },

        # remember, do not allow to use page cache
        # (it's not working because of internal filter)
        CacheKey => undef,
        CacheTTL => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $CacheKey   = 'User' . '-' . $Self->{UserID} . '-ResourcesOverview';
	
	# get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check for refresh time
    my $Refresh = '';
    if ( $Self->{UserRefreshTime} ) {
        $Refresh = 60 * $Self->{UserRefreshTime};
        my $NameHTML = $Self->{Name};
        $NameHTML =~ s{-}{_}xmsg;

        # send data to JS
        $LayoutObject->AddJSData(
            Key   => 'QueueOverview',
            Value => {
                Name        => $Self->{Name},
                NameHTML    => $NameHTML,
                RefreshTime => $Refresh,
            },
        );
    }

    # get cache object
    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    my $Content = $CacheObject->Get(
        Type => 'DashboardResourcesOverview',
        Key  => $CacheKey,
    );
    return $Content if defined $Content;

    # get configured states, get their state ID and test if they exist while we do it
    my %States;
    my $StateIDURL;
    my %ConfiguredStates = %{ $Self->{Config}->{States} };
    for my $StateOrder ( sort { $a <=> $b } keys %ConfiguredStates ) {
        my $State = $ConfiguredStates{$StateOrder};

        # check if state is found, to record StateID
        my $StateID = $Kernel::OM->Get('Kernel::System::State')->StateLookup(
            State => $State,
        ) || '';
        if ($StateID) {
            $States{$State} = $StateID;

            # append StateID to URL for search string
            $StateIDURL .= "StateIDs=$StateID;";
        }
        else {

            # state does not exist, skipping
            delete $ConfiguredStates{$StateOrder};
        }
    }

	#get user object
	my $UserObject = $Kernel::OM->Get('Kernel::System::User');
	
	my %UserList = $UserObject->UserList(
        Type          => 'Short', 
        Valid         => 1,       
        NoOutOfOffice => 0, 
    );

	my $Sort = $Self->{Config}->{Sort} || '';

    my %ResourcesToID;
    my $ResourcesIDURL;

	# lookup users, add their UserID to new hash (needed for Search)
    RESOURCES:
    for my $ResourcesID ( sort keys %UserList ) {
		
        # add users to reverse hash
        $ResourcesToID{ $UserList{$ResourcesID} } = $ResourcesID;

        # add users to SearchURL
        $ResourcesIDURL .= "OwnerIDs=$ResourcesID;";
    }

	 # Prepare ticket count.
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my @ResourcesIDs     = sort keys %UserList;
    if ( !@ResourcesIDs ) {
        @ResourcesIDs = (999_999);
    }

	my %Results;
    for my $StateOrderID ( sort { $a <=> $b } keys %ConfiguredStates ) {

        # Run ticket search for all users (owner) and appropriate available State.
        my @StateOrderTicketIDs = $TicketObject->TicketSearch(
            UserID   => $Self->{UserID},
            Result   => 'ARRAY',
			OwnerIDs => \@ResourcesIDs,
            States   => [ $ConfiguredStates{$StateOrderID} ],
            Limit    => 100_000,
        );

		my %OwnerCount;
		
		#return OwnerID => Count of ticket
		for my $FoundTicketID (@StateOrderTicketIDs) 
		{   
			my ($OwnerID, $Owner) = $TicketObject->OwnerCheck(
				TicketID => $FoundTicketID,
			);
			
			if ( exists($OwnerCount{$OwnerID}) )
			{
				$OwnerCount{$OwnerID} = $OwnerCount{$OwnerID}+1;
			}
			else
			{
				$OwnerCount{$OwnerID} = 1;
			}
        }

        # Gather ticket count for corresponding Owner<-> State.
        for my $ResourcesID (@ResourcesIDs) {
            push @{ $Results{ $UserList{$ResourcesID} } },
                $OwnerCount{$ResourcesID} ? $OwnerCount{$ResourcesID} : 0;
        }
    }

	# build header
    my @Headers = ( 'Resources Owner', );
    for my $StateOrder ( sort { $a <=> $b } keys %ConfiguredStates ) {
        push @Headers, $ConfiguredStates{$StateOrder};
    }

    for my $HeaderItem (@Headers) {
        $LayoutObject->Block(
            Name => 'ContentLargeTicketResourcesOverviewHeaderStatus',
            Data => {
                Text => $HeaderItem,
            },
        );
    }

    my $HasContent;

	# iterate over all owner, print results;
    my @StatusTotal;
    RESOURCE:
    for my $Resource ( sort values %UserList ) {

        # Hide empty owner
        if ( !grep { defined $_ && $_ > 0 } @{ $Results{$Resource} } ) {
            next RESOURCE;
        }

        $HasContent++;
		
		##get user fullname
		my %UserFull = $UserObject->GetUserData(
			User          => $Resource,
			Valid         => 1,         
			NoOutOfOffice => 0,
		);
	
		
        $LayoutObject->Block(
            Name => 'ContentLargeTicketResourcesOverviewResourcesName',
            Data => {
                ResourceID   => $ResourcesToID{$Resource},
                ResourceName => $UserFull{UserFullname},
            }
        );

        # iterate over states
        my $Counter = 0;
        my $RowTotal;
        for my $StateOrderID ( sort { $a <=> $b } keys %ConfiguredStates ) {
            $LayoutObject->Block(
                Name => 'ContentLargeTicketResourcesOverviewResourcesResults',
                Data => {
                    Number  => $Results{$Resource}->[$Counter],
                    OwnerID => $ResourcesToID{$Resource},
                    StateID => $States{ $ConfiguredStates{$StateOrderID} },
                    State   => $ConfiguredStates{$StateOrderID},
                    Sort    => $Sort,
                },
            );
            $RowTotal                   += $Results{$Resource}->[$Counter] || 0;
            $StatusTotal[$StateOrderID] += $Results{$Resource}->[$Counter] || 0;
            $Counter++;
        }

        # print row (owner) total
        $LayoutObject->Block(
            Name => 'ContentLargeTicketResourcesOverviewResourcesTotal',
            Data => {
                Number   => $RowTotal,
                OwnerID  => $ResourcesToID{$Resource},
                StateIDs => $StateIDURL,
                Sort     => $Sort,
            },
        );

    }

	if ($HasContent) {
        $LayoutObject->Block(
            Name => 'ContentLargeTicketResourcesOverviewStatusTotalRow',
        );

        for my $StateOrderID ( sort { $a <=> $b } keys %ConfiguredStates ) {
            $LayoutObject->Block(
                Name => 'ContentLargeTicketResourcesOverviewStatusTotal',
                Data => {
                    Number   => $StatusTotal[$StateOrderID],
                    OwnerID => $ResourcesIDURL,
                    StateID  => $States{ $ConfiguredStates{$StateOrderID} },
                    Sort     => $Sort,
                },
            );
        }
    }
    else {
        $LayoutObject->Block(
            Name => 'ContentLargeTicketResourcesOverviewNone',
            Data => {
                ColumnCount => ( scalar keys %ConfiguredStates ) + 2,
            }
        );
    }

    $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardTicketResourcesOverview',
        Data         => {
            %{ $Self->{Config} },
            Name => $Self->{Name},
        },
        AJAX => $Param{AJAX},
    );

    # cache result
    if ( $Self->{Config}->{CacheTTLLocal} ) {
        $CacheObject->Set(
            Type  => 'DashboardResourcesOverview',
            Key   => $CacheKey,
            Value => $Content || '',
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60,
        );
    }

    return $Content;

}

1;
