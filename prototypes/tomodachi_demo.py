import random
import json

class Tomodachi:
    def __init__(self):
        self.level = "0-1_years"
        self.words_learned = set()
        self.current_words = []
        self.load_vocabulary()
        
    def load_vocabulary(self):
        # Simple vocabulary data
        self.vocabulary = {
            "0-1_years": {
                "words": ["は", "を", "が", "か", "で", "に", "の", "と", "おはよう", "こんにちは", "ありがとう", "ごめん", "はい", "私", "です", "ます", "言う", "ある", "行く", "来る", "食べる", "見る", "聞く", "好き", "いい", "悪い", "大きい", "小さい", "高い", "低い", "新しい", "古い", "いいね", "そう", "そうか", "いいよ", "お願い", "ありがとう", "こんにちは", "おやすみ"],
                "sentences": ["おはよう", "こんにちは", "ありがとう", "ごめん", "はい", "私 です", "言う", "ある", "行く", "来る", "食べる", "見る", "聞く", "好き", "いい", "悪い", "大きい", "小さい", "高い", "低い", "新しい", "古い", "いいね", "そう", "そうか", "いいよ", "お願い"],
                "proficiency_threshold": 0.7
            }
        }
        self.current_words = self.vocabulary[self.level]["words"]
        self.sentences = self.vocabulary[self.level]["sentences"]
    
    def get_random_sentence(self):
        return random.choice(self.sentences)
    
    def check_user_response(self, user_input):
        # Simple check - see if user used any learned words
        user_words = user_input.split()
        learned_words = set(self.current_words)
        matched_words = [word for word in user_words if word in learned_words]
        
        # Calculate mastery (percentage of learned words used)
        if user_words:
            mastery = len(matched_words) / len(user_words)
        else:
            mastery = 0
            
        return {
            "matched_words": matched_words,
            "mastery": mastery,
            "total_words": len(user_words),
            "matched_count": len(matched_words)
        }
    
    def progress_level(self):
        # Simple progression - just for demo
        print("🎉 Tomodachi is growing! Level up!")
        return True
    
    def chat(self):
        print("🌟 Tomodachi hatched! Let's learn together!")
        print("I only understand simple words right now...")
        
        while True:
            # Tomodachi says something
            message = self.get_random_sentence()
            print(f"\nTomodachi: {message}")
            
            # User responds
            user_input = input("Your turn: ")
            
            # Check response
            result = self.check_user_response(user_input)
            print(f"Your mastery: {result['mastery']:.2f}")
            
            if result['mastery'] >= self.vocabulary[self.level]["proficiency_threshold"]:
                print("✨ Great job! You're understanding more!")
                if self.progress_level():
                    print("Let's learn new words!")
                    break
            else:
                print("Try again with words I know!")

# Run the demo
if __name__ == "__main__":
    tomodachi = Tomodachi()
    tomodachi.chat()
