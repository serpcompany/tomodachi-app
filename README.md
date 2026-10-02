**ZENBU APP IDEA - "TOMODACH"**

**Premise:** You get a "newly hatched" tomodachi pet/friend. It talks to you only using words appropriate for its age (so when it's a baby, it only knows simple words like "herfo"). 

The more you talk to it and demonstrate your understanding of its speech, the more it "grows" and learns new words. 

**In other words:** You are the baby caretaker who learns like a toddler, but the learning system levels up slowly. 

In a way, it kind of forces you to learn:
"Your level of Japanese is equal to a # year old" - if the tomodachi is 3 years old, it will know how to converse at the same level as a Japanese 3-year-old.

So if you can hold a conversation with it, you have the language grasp/capacity of a 3-year-old.

**Bonus feature:** You could have it like one of those "ChatGPT pets" on your computer or phone and "watch a show together."

If it's 3 years old, maybe it would watch SpongeBob in Japanese with you and chat during it (like you're watching it with your real 3-year-old kid).

---

okay so based on this idea... 

how trivial or difficult would it be with all the capable ai models and apis now?

they can talk real time already. they can remember things. they can follow some kinds of rules based on stuff like "what level/age" it is...

the things that we would need to have access to is like:

- what words to japanese people konw at each age
- what things do they do/like/watch for their age
- some way to kinda of gauge/measure the users proficiency (do they understand the convo) to know when to start leveling it up

---- seems kinda easy?

---


**What's already possible:**
- **Real-time conversation** - All major LLMs can chat seamlessly
- **Context memory** - Models can remember conversation history and adjust responses
- **Age-appropriate language** - You can prompt a model to "speak like a 5-year-old" or "use simple vocabulary"
- **Adaptive learning** - Models can adjust complexity based on user responses

**The main challenges:**
1. **Age-appropriate vocabulary database** - This would need to be built or sourced (though you could start with existing child language research)
2. **Proficiency assessment** - You'd need a system to detect when users understand the current level
3. **Content matching** - Knowing what 3-year-olds watch/like in Japanese

**How you'd implement it:**
- Use a base LLM with prompts like "respond as a 3-year-old Japanese child"
- Implement a "proficiency checker" that analyzes user responses to determine if they're understanding
- Create a progression system that gradually increases complexity
- Add content recommendations based on age-appropriate Japanese media

**It's definitely doable** - you're essentially creating a language learning tool with gamification elements. The core AI technology exists, you just need to build the "age progression" and "proficiency tracking" systems.

---


**Exactly!** That's a brilliant approach. Here's how you could structure it:

**Word Level Progression System:**
- **Level 1 (1-2 years)**: 20-30 basic words ( mama, papa, dog, cat, eat, drink)
- **Level 2 (3-4 years)**: 50-100 words (more verbs, basic sentences)
- **Level 3 (5-6 years)**: 100-200 words (complex sentences, topics like school, friends)

**Implementation:**
1. **Word tracking**: Model keeps track of which words the user understands/uses
2. **Mastery threshold**: When user demonstrates 70-80% mastery of current level words, level up
3. **Gradual transition**: Instead of jumping levels, introduce 10-20% of next level words gradually

**Example flow:**
- User at Level 1: "Mama, dog, eat"
- User demonstrates mastery: "Mama, dog, eat, water, more"
- Level 2 begins: "Mama, dog, eat, water, more, school, friend"
- User learns 80% of Level 2 words → Level 3

**Bonus features:**
- **Spelling/grammar tracking** (not just vocabulary)
- **Topic-based progression** (animals → family → school → hobbies)
- **Interactive learning** where the tomodachi asks questions to test understanding

This is actually very similar to how language learning apps like Duolingo work - it's just adding the "age-appropriate" and "pet" elements to make it more engaging. The AI can handle the adaptive learning part quite well now.


## Questions & uncertainties

Q: how does a conversation work at the super low levels when all they know is like single word sentences "hello", "goodbye", "dog", etc?
A: maybe if that "coucou mac companion notch" heyclicky type thing is open source or we made one it could say those words if like the user is looking at a picture of a dog on the computer... or maybe it could like bring up a picture of a dog and say 'dog'..?

