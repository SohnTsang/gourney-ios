// supabase/functions/lists-get-popular/index.ts
// Returns popular lists based on weighted score

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Check Authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      console.error('[lists-get-popular] Missing Authorization header')
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Create admin client for auth verification
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Verify JWT using service role
    const jwt = authHeader.replace('Bearer ', '')
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(jwt)

    console.log('[lists-get-popular] Auth check:', { 
      hasUser: !!user, 
      userId: user?.id,
      hasError: !!authError,
      errorMessage: authError?.message 
    })

    if (authError || !user) {
      console.error('[lists-get-popular] Auth failed:', authError)
      return new Response(JSON.stringify({ error: 'Unauthorized', details: authError?.message }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    console.log('✅ [lists-get-popular] User authenticated:', user.id)

    // Create client for data queries
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // Read limit from request body
    let limit = 20
    try {
      const body = await req.json()
      if (body.limit) {
        limit = Math.min(parseInt(body.limit), 50)
      }
    } catch {
      // Default to 20 if no body
    }

    // Query popular lists with weighted scoring
    // Score = (likes × 3) + (views × 0.1) + (item_count × 0.5) + recency_bonus
    const { data: lists, error } = await supabaseClient
      .rpc('get_popular_lists', {
        p_viewer: user.id,
        p_limit: limit
      })

    if (error) {
      console.error('Error fetching popular lists:', error)
      return new Response(JSON.stringify({ error: 'Failed to fetch popular lists' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ lists: lists || [] }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})