#
# This tests the basic database CRUD functions of course users.
#
use warnings;
use strict;

BEGIN {
	use File::Basename qw/dirname/;
	use Cwd qw/abs_path/;
	$main::test_dir = abs_path( dirname(__FILE__) );
	$main::lib_dir  = dirname( dirname($main::test_dir) ) . '/lib';
}

use lib "$main::lib_dir";

use Text::CSV qw/csv/;
use Data::Dump qw/dd/;
use List::Util qw(uniq);
use Test::More;
use Test::Exception;
use Try::Tiny;

use DB::WithParams;
use DB::WithDates; 
use DB::Schema;
use DB::TestUtils qw/loadCSV removeIDs/;

# load the database
my $db_file = "$main::test_dir/sample_db.sqlite";
my $schema  = DB::Schema->connect("dbi:SQLite:$db_file");

# $schema->storage->debug(1);  # print out the SQL commands.

my $course_rs = $schema->resultset("Course");
my $user_rs   = $schema->resultset("User");

## get a list of users from the CSV file
my @students = loadCSV("$main::test_dir/sample_data/students.csv");

## filter only precalc students
my @precalc_students = grep { $_->{course_name} eq "Precalculus" } @students;
for my $student (@precalc_students) {
	delete $student->{course_name};
}
@precalc_students = sort { $a->{login} cmp $b->{login} } @precalc_students;

## test getUsers

my @users                    = $user_rs->getUsers( { course_name => "Precalculus" } );
my @precalc_students_from_db = sort { $a->{login} cmp $b->{login} } @users;
my $precalc_students_from_db = removeCourseUserIDs( \@precalc_students_from_db );

sub removeCourseUserIDs {
	my $users = shift;
	for my $user (@$users) {
		removeIDs($user); 
	}
}

is_deeply( \@precalc_students, \@precalc_students_from_db, "getUsers: get users from a course" );

## getUsers: test that an unknown course results in an error

try {
	$user_rs->getUsers( { course_name => "unknown_course" } );
}
catch {
	ok($_->isa('CourseNotFoundException'),"getUsers: undefined course_name");
};

try {
	$user_rs->getUsers( { course_id => -3 } );
}
catch {
	ok($_->isa('CourseNotFoundException'),"getUsers: undefined course_id");
};

## test getUser

my $user = $user_rs->getUser( { course_name => "Precalculus", login => $precalc_students[0]->{login} } );
removeIDs($user); 

is_deeply( $precalc_students[0], $user, "getUser: get one user" );

## getUser: test that an unknown course results in an error

try {
	$user_rs->getUser( { course_name => "unknown_course", login => "barney" } );
}
catch {
	ok($_->isa('CourseNotFoundException'),"getUser: undefined course");
};

## getUser: test that an unknown user results in an error

try {
	$user_rs->getUser( { course_name => "Precalculus", login => "unknown_user" } );
}
catch {
	ok($_->isa('UserNotInCourseException'),"getUser: undefined user");
};

## addUser:  add a user to a course

my $user_params = {
	login       => "quimby",
	first_name  => "Joe",
	last_name   => "Quimby",
	email       => 'mayor_joe@springfield.gov',
	student_id  => "12345",
	role       => "student",
	params      => {},
	recitation  => undef,
	section     => undef
};

$user = $user_rs->addUser( { course_name => "Arithmetic" }, $user_params );

removeIDs($user); 
delete $user_params->{course_name};

is_deeply( $user_params, $user, "addUser: add a user to a course" );

## addUser: check that if the course doesn't exist, an error is thrown:

try {
	$user_rs->addUser( { course_name => "unknown_course", login => "barney" } );
}
catch {
	ok($_->isa("CourseNotFoundException"),"addUser: the course doesn't exist");
};


## addUser: the course exists, but the user is already a member.

try {
	$user_rs->addUser( { course_name => "Arithmetic"}, {login => "moe" } );
}
catch {
	ok($_->isa("UserAlreadyInCourseException"),"addUser: the user is already a member");
};

## updateUser: check that the user updates.

my $updated_user = {
	params=> {email=> 'joe_the_mayor@juno.com',comment => 'Mayor Joe is the best!!'}
};

for my $key (keys %$updated_user) {
	$user_params->{$key} = $updated_user->{$key};
}

my $user_from_db = $user_rs->updateUser( 
	{ course_name => 'Arithmetic', login => 'quimby' }, $updated_user );

removeIDs($user_from_db); 

is_deeply( $user_params, $user_from_db, "updateUser: update a single user in an existing course." );

## updateUser: check that if the course doesn't exist, an error is thrown:
try {
	$user_rs->updateUser( { course_name => "unknown_course", login => "barney" },$updated_user );
}
catch {
	ok($_->isa("CourseNotFoundException"),"updateUser: the course doesn't exist");
};

## updateUser: check that if the course exists, but the user not a member.
try {
	$user_rs->updateUser( { course_name => "Arithmetic", login => "bart" }, $updated_user);
}
catch {
	ok($_->isa("UserNotInCourseException"),"updateUser: the user is not a member of the course");
};

## updateUser: send in wrong information

try {
	$user_rs->updateUser( { course_name => "Arithmetic", login_name => "bart"},$updated_user);
}
catch {
	ok($_->isa("ParametersException"),"updateUser: the incorrect information is passed in.");
};

## updateUser: update a user with nonvalid fields

try {
	$user_rs->updateUser({ course_name => "Arithmetic", login=> "quimby"}, {sleeps_in_class => 1});
}
catch {
	ok($_->isa("ParametersException"),"updateUser: an invalid field is set");
};


## deleteUser: delete a single user from a course

my $deleted_user;

my $dont_delete_users; # switch to not delete added users.   

SKIP: {

	skip "delete added users", 4 if $dont_delete_users;

	$deleted_user = $user_rs->deleteUser( { course_name => "Arithmetic", login => "quimby" } );
	removeIDs($deleted_user); 

	is_deeply( $user_params, $deleted_user, 'deleteUser: delete a user from a course' );



## deleteUser: check that if the course doesn't exist, an error is thrown:

	try {
		$user_rs->deleteUser( { course_name => "unknown_course", login => "barney" });
	}
	catch {
		ok($_->isa("CourseNotFoundException"),"deleteUser: the course doesn't exist");
	};


## deleteUser: check that if the course exists, but the user not a member.


	try {
		$user_rs->deleteUser( { course_name => "Arithmetic", login => "bart" });
	}
	catch {
		ok($_->isa("UserNotInCourseException"),"deleteUser: the user is not a member of the course");
	};


## deleteUser: send in login_name instead of login

	try {
		$user_rs->deleteUser( { course_name => "Arithmetic", login_name => "bart"});
	}
	catch {
		ok($_->isa("ParametersException"),"deleteUser: the incorrect information is passed in.");
	};



### delete the global User that was created. 

	$user_rs->deleteGlobalUser({login => $user_params->{login}});
}

done_testing;

1;
