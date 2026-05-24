import { z } from "zod";

const tools = {
    read: z.object({
        name: z.string().describe(
            "The file path to read. Can be an absolute path or relative to the current working directory. Do not wrap the string in quotes or markdown backticks."
        ),
    }).describe(
        "Reads and retrieves the entire text content of a specified file on the host machine. Best used for inspectable formats like scripts (.ts, .py, .sh), config files (.json, .xml, .yaml), or logs. Avoid using this on binary files (like images, archives, or compiled executables) or exceptionally large files that could flood the context window."
    ),
    bash: z.object({
        command: z.string().describe(
            "The exact shell command to execute. Supports multiline scripts, piping (|), and redirection (>). Do not include conversational text or markdown code blocks here."
        ),
    }).describe(
        "Executes an arbitrary command in a non-interactive bash shell on the host machine. Current environment: Linux. Use this to inspect files, manage directories, run processes, or install dependencies. WARNING: Ensure commands are safe, complete, and do not hang indefinitely (avoid un-flagged commands like interactive 'sudo' or raw 'npm start')."
    ),
};

function parse(name: string, obj: z.ZodObject): string {
    const schema = obj.toJSONSchema({ target: "openapi-3.0" });
    return JSON.stringify({
        type: "function" as const,
        function: {
            name, description: schema.description,
            parameters: schema.properties,
        }
    }, null, 0);
}

console.log(Object.entries(tools).map(([key, value]) => parse(key, value)).join("\n"));
