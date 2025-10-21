//
//  DebugAuthHelper.swift
//  gourney
//
//  Debug helper for testing authentication flow
//

import Foundation

struct DebugAuthHelper {
    
    /// Print current auth state for debugging
    static func printAuthState(_ authManager: AuthManager) {
        print("🔍 ===== AUTH STATE DEBUG =====")
        print("🔍 isAuthenticated: \(authManager.isAuthenticated)")
        print("🔍 needsProfileCompletion: \(authManager.needsProfileCompletion)")
        print("🔍 isLoading: \(authManager.isLoading)")
        print("🔍 currentUser: \(authManager.currentUser?.handle ?? "nil")")
        print("🔍 errorMessage: \(authManager.errorMessage ?? "nil")")
        print("🔍 hasToken: \(SupabaseClient.shared.getAuthToken() != nil)")
        print("🔍 ============================")
    }
    
    /// Test if user can create profile
    static func testProfileCreation() async {
        let client = SupabaseClient.shared
        
        guard let token = client.getAuthToken() else {
            print("❌ No auth token found")
            return
        }
        
        // Extract user ID from token
        let segments = token.components(separatedBy: ".")
        guard segments.count > 1 else {
            print("❌ Invalid token format")
            return
        }
        
        var base64 = segments[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = json["sub"] as? String else {
            print("❌ Could not extract user ID from token")
            return
        }
        
        print("🔍 Testing profile creation for user ID: \(userId)")
        
        do {
            let testBody: [String: Any] = [
                "id": userId,
                "handle": "debug_test_\(Int.random(in: 1000...9999))",
                "display_name": "Debug Test User",
                "locale": "en"
            ]
            
            let response: [User] = try await client.post(
                path: "/rest/v1/users",
                body: testBody
            )
            
            print("✅ Profile creation test PASSED")
            print("✅ Created user: @\(response.first?.handle ?? "unknown")")
            
        } catch let error as APIError {
            print("❌ Profile creation test FAILED")
            print("❌ Error: \(error)")
            print("❌ Description: \(error.errorDescription ?? "none")")
        } catch {
            print("❌ Profile creation test FAILED")
            print("❌ Error: \(error)")
        }
    }
    
    /// Verify RLS policies are set correctly
    static func verifyRLSPolicies() {
        print("🔍 ===== RLS POLICY CHECK =====")
        print("🔍 Run this SQL in Supabase SQL Editor:")
        print("""
        
        SELECT 
          tablename,
          policyname,
          cmd,
          permissive,
          roles,
          qual,
          with_check
        FROM pg_policies 
        WHERE tablename = 'users' 
          AND schemaname = 'public'
        ORDER BY cmd;
        
        """)
        print("🔍 Expected policies:")
        print("🔍 1. users_select_policy (SELECT)")
        print("🔍 2. users_update_own (UPDATE)")
        print("🔍 3. users_insert_policy (INSERT) ← CRITICAL")
        print("🔍 ============================")
    }
}
