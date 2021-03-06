module PublicProgressReports
    extend ActiveSupport::Concern

    def last_completed_diagnostic
      diagnostic_activity_ids = ActivityClassification.find(4).activities.map(&:id)
      current_user.classroom_activities.
                  joins(activity_sessions: :classroom_activity).
                  where('activity_sessions.state = ? AND activity_sessions.activity_id IN (?)', 'finished', diagnostic_activity_ids).
                  order('created_at DESC').
                  limit(1).
                  first
    end

    def activity_session_report(activity_session_id)
      act_sesh = ActivitySession.includes({ classroom_activity: [:classroom, :unit]}, :user).find(activity_session_id)
      classroom_activity = act_sesh.try(:classroom_activity)
      unit_id = classroom_activity.try(:unit).id
      activity_id = classroom_activity.try(:activity).id
      classroom_id = classroom_activity.try(:classroom).id
      user = act_sesh.try(:user)
      if user && classroom_id && classroom_id
        {url: "/teachers/progress_reports/diagnostic_reports#/u/#{unit_id}/a/#{activity_id}/c/#{classroom_id}/student_report/#{user.id}"}
      end
    end

    def default_diagnostic_url
      ca = last_completed_diagnostic
      if ca
        custom_url = "#u/#{ca.unit.id}/a/#{ca.activity_id}/c/#{ca.classroom_id}"
        return "/teachers/progress_reports/diagnostic_reports/#{custom_url}/students"
      else
        return "/teachers/progress_reports/diagnostic_reports/#not_completed"
      end
    end

    def results_by_question(params)
      classroom_activity = ClassroomActivity.find_by(classroom_id: params[:classroom_id], activity_id: params[:activity_id], unit_id: params[:unit_id])
      questions = Hash.new{|h,k| h[k]={} }
      all_answers = classroom_activity.activity_session_metadata
      all_answers.each do |answer|
        curr_quest = questions[answer["questionNumber"]]
        curr_quest[:correct] ||= 0
        curr_quest[:total] ||= 0
        curr_quest[:correct] += answer["questionScore"] || answer["correct"]
        curr_quest[:total] += 1
        curr_quest[:prompt] ||= answer["prompt"]
        curr_quest[:question_number] ||= answer["question_number"]
        if answer["attemptNumber"] == 1 || !curr_quest[:instructions]
          direct = answer["directions"] || answer["instructions"] || ""
          curr_quest[:instructions] ||= direct.gsub(/(<([^>]+)>)/i, "").gsub("()", "").gsub("&nbsp;", "")
        end
      end
      # TODO: change the diagnostic reports so they take in a hash of classrooms -- this is just
      # being converted to an array because that is what the diagnostic reports expect
      questions_arr = questions.map do |k,v|
        {question_id: k,
         score: ((v[:correct].to_f/v[:total].to_f) * 100).round,
         prompt: v[:prompt],
         instructions: v[:instructions]
        }
      end
      questions_arr
    end

    def classrooms_with_students_that_completed_activity unit_id, activity_id
      h = {}
      unit = Unit.find(unit_id)
      class_ids = current_user.classrooms_i_teach.map(&:id)
      #without definining class ids, it may default to a classroom activity from a non-existant classroom
      class_acts = unit.classroom_activities.where(activity_id: activity_id, classroom_id: class_ids)

      class_acts.each do |ca|
        classroom = ca.classroom.attributes
        activity_sessions = ca.activity_sessions.completed
        activity_sessions.each do |activity_session|
          class_id = classroom['id']
          h[class_id] ||= classroom
          h[class_id][:students] ||= []
          if h[class_id][:students].exclude? activity_session.user
             h[class_id][:students] << activity_session.user
          end
          h[class_id][:classroom_activity_id] = ca.id
        end
      end

      # TODO: change the diagnostic reports so they take in a hash of classrooms -- this is just
      # being converted to an array because that is what the diagnostic reports expect
      h.map{|k,v| v}
    end

    def results_for_classroom unit_id, activity_id, classroom_id
      classroom_activity = ClassroomActivity.find_by(classroom_id: classroom_id, activity_id: activity_id, unit_id: unit_id)
      activity = classroom_activity.activity
      activity_sessions = classroom_activity.activity_sessions.where(is_final_score: true).includes(:user, concept_results: :concept)
      classroom = Classroom.find(classroom_id)
      scores = {
        id: classroom.id,
        name: classroom.name
      }
      scores[:students] = activity_sessions.map do |activity_session|
          student = activity_session.user
          formatted_concept_results = get_concept_results(activity_session)
        {
            activity_classification: ActivityClassification.find(activity.activity_classification_id).key,
            id: student.id,
            name: student.name,
            time: get_time_in_minutes(activity_session),
            number_of_questions: formatted_concept_results.length,
            concept_results: formatted_concept_results,
            score: get_average_score(formatted_concept_results)
          }
      end
      scores
    end


    def get_time_in_minutes activity_session
      if activity_session.started_at && activity_session.completed_at
        return ((activity_session.completed_at - activity_session.started_at) / 60).round()
      else
        return 'Untracked'
      end
    end

    def get_concept_results activity_session
      activity_session.concept_results.group_by{|cr| cr[:metadata]["questionNumber"]}.map { |key, cr|
        # if we don't sort them, we can't rely on the first result being the first attemptNum
        # however, it would be more efficient to make them a hash with attempt numbers as keys
        cr.sort!{|x,y| x[:metadata]['attemptNumber'] <=> y[:metadata]['attemptNumber']}
        directfirst = cr.first[:metadata]["directions"] || cr.first[:metadata]["instructions"] || ""
        hash = {
          directions: directfirst.gsub(/(<([^>]+)>)/i, "").gsub("()", "").gsub("&nbsp;", ""),
          prompt: cr.first[:metadata]["prompt"],
          answer: cr.first[:metadata]["answer"],
          score: get_score_for_question(cr),
          concepts: cr.map { |crs|
            direct = crs[:metadata]["directions"] || crs[:metadata]["instructions"] || ""
            {
              id: crs.concept_id,
              name: crs.concept.name,
              correct: crs[:metadata]["correct"] == 1,
              attempt: crs[:metadata]["attemptNumber"] || 1,
              answer: crs[:metadata]["answer"],
              directions: direct.gsub(/(<([^>]+)>)/i, "").gsub("()", "").gsub("&nbsp;", "")
            }
          },
          question_number: cr.first[:metadata]["questionNumber"]
        }
        if cr.first[:metadata]['questionScore']
          hash[:questionScore] = cr.first[:metadata]['questionScore']
        end
        hash
      }
    end

    def get_score_for_question concept_results
      if concept_results.length > 0 && concept_results.first[:metadata]['questionScore']
        concept_results.first[:metadata]['questionScore'] * 100
      else
        concept_results.inject(0) {|sum, crs| sum + crs[:metadata]["correct"]} / concept_results.length * 100
      end
    end

    def get_average_score formatted_results
      (formatted_results.inject(0) {|sum, crs| sum + crs[:score]} / formatted_results.length).round()
    end


    def get_recommendations_for_classroom classroom_id
      classroom = Classroom.find(classroom_id)
      diagnostic = Activity.find(413)
      students = classroom.students
      activity_sessions = students.map do |student|
        student.activity_sessions.includes(concept_results: :concept).find_by(activity_id: diagnostic.id, is_final_score: true)
      end
      activity_sessions.compact!
      activity_sessions_counted = activity_sessions_with_counted_concepts(activity_sessions)
      unique_students = activity_sessions.map {|activity_session| user = activity_session.user; {id: user.id, name: user.name}}
                                         .sort_by {|stud| stud[:name].split()[1]}
      recommendations = Recommendations.new.diagnostic.map do |activity_pack_recommendation|
        students = []
        activity_sessions_counted.each do |activity_session|
          activity_pack_recommendation[:requirements].each do |req|
            if activity_session[:concept_scores][req[:concept_id]] < req[:count]
              students.push(activity_session[:user_id])
              break
            end
          end
        end
        return_value_for_recommendation(students, activity_pack_recommendation)
      end
      {
        students: unique_students,
        recommendations: recommendations
      }
    end

    def return_value_for_recommendation students, activity_pack_recommendation
      {
        activity_pack_id: activity_pack_recommendation[:activityPackId],
        name: activity_pack_recommendation[:recommendation],
        students: students
      }
    end

    def activity_sessions_with_counted_concepts activity_sessions
      activity_sessions.map do |activity_session|
        {
          user_id: activity_session.user_id,
          concept_scores: concept_results_by_count(activity_session)
        }
      end
    end

    def concept_results_by_count activity_session
      hash = Hash.new(0)
      activity_session.concept_results.each do |concept_result|
        hash[concept_result.concept.uid] += concept_result["metadata"]["correct"]
      end
      hash
    end

end
