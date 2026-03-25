import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { pincode } = await req.json();

    if (!pincode || typeof pincode !== "string" || pincode.length !== 4) {
      return new Response(
        JSON.stringify({ error: "Invalid code." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Look up team member by pincode
    const { data: member, error: memberError } = await admin
      .from("team_members")
      .select("user_id, name")
      .eq("pincode", pincode)
      .maybeSingle();

    if (memberError) throw memberError;
    if (!member) {
      return new Response(
        JSON.stringify({ error: "Invalid code." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get user email from auth
    const { data: userData, error: userError } = await admin.auth.admin.getUserById(member.user_id);
    if (userError || !userData?.user?.email) {
      return new Response(
        JSON.stringify({ error: "User not found." }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Generate a magic link token for this user
    const { data: linkData, error: linkError } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: userData.user.email,
    });

    if (linkError || !linkData) {
      throw linkError || new Error("Failed to generate login link");
    }

    // Extract the token hash and use it to verify OTP
    const tokenHash = linkData.properties?.hashed_token;
    if (!tokenHash) {
      throw new Error("No token hash returned");
    }

    // Use verifyOtp with the token hash to get a valid session
    const anonClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: sessionData, error: sessionError } = await anonClient.auth.verifyOtp({
      token_hash: tokenHash,
      type: "magiclink",
    });

    if (sessionError || !sessionData.session) {
      throw sessionError || new Error("Failed to create session");
    }

    return new Response(
      JSON.stringify({
        session: sessionData.session,
        user: sessionData.user,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message || "Server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
