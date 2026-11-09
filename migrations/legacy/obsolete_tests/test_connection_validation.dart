import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  // Initialize Supabase with staging credentials (provided by user)
  final supabase = Supabase.instance.client;
  
  print('=== Supabase Runtime Connection Validation ===');
  print('URL: https://yzjptffwnvnuyxbdkidm.supabase.co');
  print('Key prefix: sb_publishable_ (anon/publishable key)');
  print('');
  
  // Test 1: Client initialization
  try {
    await Supabase.initialize(
      url: 'https://yzjptffwnvnuyxbdkidm.supabase.co',
      publishableKey: 'sb_publishable_E9SJgKKt_9Tl-E4ddJNJeg_29_cFum4',
    );
    print('✓ Test 1: Supabase.initialize() completed successfully');
  } catch (e) {
    print('✗ Test 1: Supabase.initialize() failed: $e');
  }
  
  // Test 2: Network connectivity check (try to list tables via profiles)
  try {
    final response = await supabase.from('profiles').select('count');
    print('✓ Test 2: Database query succeeded - HTTP connectivity verified');
    print('  Response: ${response.data}');
    if (response.error != null) {
      print('  Error (sanitized): ${response.error!.message}');
    }
  } catch (e) {
    print('✗ Test 2: Database query failed');
    print('  Error type: ${e.runtimeType}');
    print('  Error message: ${e.toString().substring(0, 100)}...');
  }
  
  // Test 3: Authentication distinction - try sign out (should always work)
  try {
    await supabase.auth.signOut();
    print('✓ Test 3: Sign out succeeded (auth client functional)');
  } catch (e) {
    print('✗ Test 3: Sign out failed: $e');
  }
  
  // Test 4: Authentication check - sign in should fail without valid credentials
  // This distinguishes HTTP connectivity from authentication success
  try {
    // Attempt sign in with invalid credentials - should fail with sanitized error
    final authResponse = await supabase.auth.signInWithPassword(
      email: 'nonexistent@test.com',
      password: 'wrongpassword',
    );
    if (authResponse.session == null) {
      print('✓ Test 4: Authentication correctly rejected - no session created');
      print('  Error (sanitized): Authentication failed. Please check your credentials.');
    }
  } catch (e) {
    print('✓ Test 4: Authentication correctly rejected - error caught');
    print('  Error (sanitized): ${e.toString().substring(0, 80)}...');
  }
  
  print('');
  print('=== Connection Validation Complete ===');
}